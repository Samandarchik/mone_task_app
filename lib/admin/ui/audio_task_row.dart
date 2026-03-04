import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/provider/video_player_provider.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

class AudioTaskRow extends StatefulWidget {
  final CheckerCheckTaskModel task;
  final DateTime selectedDate;

  const AudioTaskRow({
    super.key,
    required this.task,
    required this.selectedDate,
  });

  @override
  State<AudioTaskRow> createState() => _AudioTaskRowState();
}

class _AudioTaskRowState extends State<AudioTaskRow>
    with SingleTickerProviderStateMixin {
  // ── Record ────────────────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isSending = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  late AnimationController _pulseCtrl;

  // ── Player ────────────────────────────────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  bool _isCompleted = false;

  String? _localAudioUrl;

  String? get _audioUrl => _localAudioUrl ?? widget.task.checkerAudioUrl;
  bool get _hasAudio => _audioUrl != null && _audioUrl!.isNotEmpty;
  bool get _canRecord =>
      widget.task.videoUrl != null && widget.task.videoUrl!.isNotEmpty;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _playerStateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) {
        setState(() {
          _isPlaying = s == PlayerState.playing;
          if (s == PlayerState.completed) {
            _isCompleted = true;
            _position = Duration.zero;
          } else if (s == PlayerState.playing) {
            _isCompleted = false;
          }
        });
      }
    });
    _positionSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durationSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkRecordingSignal();
  }

  /// Provider dan recording signalni tekshiradi
  void _checkRecordingSignal() {
    try {
      final provider = context.read<VideoPlayerProvider>();
      final currentTask = provider.currentTask;

      // Faqat hozirgi task uchun va signal bor bo'lsa
      if (provider.shouldStartRecording &&
          currentTask != null &&
          currentTask.taskId == widget.task.taskId &&
          !_isRecording &&
          !_isSending &&
          _canRecord) {
        provider.consumeRecordingSignal();
        // Keyingi frame da recording boshlash (context to'liq tayyor bo'lishi uchun)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startRecording();
        });
      }
    } catch (_) {
      // Provider topilmasa (masalan, player tashqarisida) — hech narsa qilmaymiz
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _recordTimer?.cancel();
    _pulseCtrl.dispose();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _fullAudioUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '${AppUrls.baseUrl}/$url';
  }

  // ── Player actions ────────────────────────────────────────────────────────

  Future<void> _togglePlay() async {
    if (_audioUrl == null) return;

    if (_isPlaying) {
      await _player.pause();
      return;
    }

    if (_isCompleted) {
      setState(() {
        _isCompleted = false;
        _position = Duration.zero;
      });
    }

    if (_localAudioUrl != null && File(_localAudioUrl!).existsSync()) {
      await _player.play(DeviceFileSource(_localAudioUrl!));
      return;
    }

    final url = _fullAudioUrl(_audioUrl!);
    await _player.play(UrlSource(url));
  }

  Future<void> _seekTo(double value) async {
    final pos = Duration(
      milliseconds: (value * _duration.inMilliseconds).round(),
    );
    await _player.seek(pos);
  }

  // ── Recorder actions ──────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofon ruxsati berilmagan')),
        );
      }
      return;
    }

    await _player.stop();

    if (mounted) setState(() => _isRecording = true);

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${widget.task.taskId}_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: path,
    );

    _recordSeconds = 0;
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });
  }

  Future<void> _stopAndSend() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    _recordTimer = null;

    final path = await _recorder.stop();
    if (mounted) setState(() => _isRecording = false);

    if (path == null || _recordSeconds < 1) {
      if (path != null) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
      return;
    }

    final file = File(path);
    if (!await file.exists()) return;

    if (mounted) setState(() => _isSending = true);

    try {
      final success = await AdminTaskService().pushAudio(
        widget.task.taskId,
        file,
        widget.selectedDate,
      );

      if (success) {
        if (mounted) setState(() => _localAudioUrl = path);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Audio yuborildi ✓' : 'Xato yuz berdi'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xato: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    _recordTimer = null;
    await _recorder.stop();
    if (mounted) setState(() => _isRecording = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canRecord) return const SizedBox.shrink();

    // Provider signalni har rebuild da tekshir
    _checkRecordingSignal();

    if (_isSending) return _buildSending();
    if (_isRecording) return _buildRecording();
    if (_hasAudio) return _buildPlayer();
    return _buildMicButton();
  }

  // ── Sub-widgets ───────────────────────────────────────────────────────────

  Widget _buildMicButton() {
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopAndSend(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_none_rounded, size: 18),
            SizedBox(width: 6),
            Text(
              'Bosib ushlab ovoz yuboring',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecording() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withOpacity(0.35 + 0.65 * _pulseCtrl.value),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmt(Duration(seconds: _recordSeconds)),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Yozilmoqda...',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
          GestureDetector(
            onTap: _cancelRecording,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.delete_outline, size: 20, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _stopAndSend,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSending() {
    return const Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 8),
        Text(
          'Yuborilmoqda...',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildPlayer() {
    final double progress = (_duration.inMilliseconds > 0)
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final bool finished = _duration > Duration.zero && _position >= _duration;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFF2196F3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                finished
                    ? Icons.replay_rounded
                    : (_isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                    activeTrackColor: const Color(0xFF2196F3),
                    inactiveTrackColor: Colors.black12,
                    thumbColor: const Color(0xFF2196F3),
                    overlayColor: const Color(0xFF2196F3).withOpacity(0.15),
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: _seekTo,
                    min: 0,
                    max: 1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(_position),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        _fmt(_duration),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_canRecord) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd: (_) => _stopAndSend(),
              child: Tooltip(
                message: 'Bosib ushlab qayta yuboring',
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.07),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mic_none_rounded,
                    size: 17,
                    color: Colors.black54,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
