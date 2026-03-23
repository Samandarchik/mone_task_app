import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioTaskRow extends StatefulWidget {
  final int taskId;
  final List<String> audioUrls;
  final DateTime selectedDate;
  final Future<bool> Function(int taskId, File file, DateTime date) onPushAudio;
  final Future<bool> Function(int taskId, DateTime date, int audioIndex)
      onDeleteAudio;

  const AudioTaskRow({
    super.key,
    required this.taskId,
    required this.audioUrls,
    required this.selectedDate,
    required this.onPushAudio,
    required this.onDeleteAudio,
  });

  /// Checker/Admin uchun convenience constructor
  factory AudioTaskRow.fromCheckerTask({
    Key? key,
    required CheckerCheckTaskModel task,
    required DateTime selectedDate,
  }) {
    final service = AdminTaskService();
    return AudioTaskRow(
      key: key,
      taskId: task.taskId,
      audioUrls: task.checkerAudioUrls,
      selectedDate: selectedDate,
      onPushAudio: (id, file, date) => service.pushAudio(id, file, date),
      onDeleteAudio: (id, date, idx) => service.deleteAudio(id, date, idx),
    );
  }

  @override
  State<AudioTaskRow> createState() => _AudioTaskRowState();
}

class _AudioTaskRowState extends State<AudioTaskRow>
    with SingleTickerProviderStateMixin {
  // ── Recorder ──────────────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isSending = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  late AnimationController _pulseCtrl;

  // ── Pointer / swipe state ─────────────────────────────────────────────────
  bool _recorderReady = false;
  bool _pendingAction = false;
  bool _swipedUp = false; // tepaga surildi → preview rejimi
  double _dragStartY = 0;

  // ── Preview rejimi ────────────────────────────────────────────────────────
  // Tepaga surib qo'yib yuborilganda: tinglash + yuborish/o'chirish
  String? _previewPath;
  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _isPreviewPlaying = false;
  Duration _previewDuration = Duration.zero;
  Duration _previewPosition = Duration.zero;
  bool _isPreviewCompleted = false;
  StreamSubscription? _previewStateSub;
  StreamSubscription? _previewPosSub;
  StreamSubscription? _previewDurSub;

  // ── Serverga yuborilgan audio player ─────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isCompleted = false;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;

  List<String> get _audioUrls => widget.audioUrls;


  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    // Serverdan audio player
    _playerStateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() {
        _isPlaying = s == PlayerState.playing;
        if (s == PlayerState.completed) {
          _isCompleted = true;
          _position = Duration.zero;
        } else if (s == PlayerState.playing) {
          _isCompleted = false;
        }
      });
    });
    _positionSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durationSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    // Preview player
    _previewStateSub = _previewPlayer.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() {
        _isPreviewPlaying = s == PlayerState.playing;
        if (s == PlayerState.completed) {
          _isPreviewCompleted = true;
          _previewPosition = Duration.zero;
        } else if (s == PlayerState.playing) {
          _isPreviewCompleted = false;
        }
      });
    });
    _previewPosSub = _previewPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _previewPosition = p);
    });
    _previewDurSub = _previewPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _previewDuration = d);
    });
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _previewPlayer.dispose();
    _recordTimer?.cancel();
    _pulseCtrl.dispose();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _previewStateSub?.cancel();
    _previewPosSub?.cancel();
    _previewDurSub?.cancel();
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

  // ── Pointer events ────────────────────────────────────────────────────────

  Future<void> _onPointerDown(PointerDownEvent event) async {
    if (_isSending) return;

    _dragStartY = event.position.dy;
    _swipedUp = false;
    _pendingAction = false;
    _recorderReady = false;

    setState(() => _isRecording = true);

    if (!await _recorder.hasPermission()) {
      if (mounted) {
        setState(() => _isRecording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofon ruxsati berilmagan')),
        );
      }
      return;
    }

    await _player.stop();
    await _previewPlayer.stop();

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${widget.taskId}_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: path,
    );

    _recorderReady = true;
    _recordSeconds = 0;
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });

    if (_pendingAction) {
      _pendingAction = false;
      if (_swipedUp) {
        await _stopForPreview();
      } else {
        await _stopAndSend();
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isRecording) return;
    final dy = _dragStartY - event.position.dy;
    if (dy > 80 && !_swipedUp) {
      setState(() => _swipedUp = true);
    } else if (dy <= 80 && _swipedUp) {
      setState(() => _swipedUp = false);
    }
  }

  Future<void> _onPointerUp(PointerUpEvent event) async {
    if (!_recorderReady) {
      _pendingAction = true;
      return;
    }
    if (_swipedUp) {
      await _stopForPreview();
    } else {
      await _stopAndSend();
    }
  }

  // ── Recording actions ─────────────────────────────────────────────────────

  /// Tepaga surilmagan → to'g'ridan-to'g'ri yuborish
  Future<void> _stopAndSend() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    _recordTimer = null;

    final path = await _recorder.stop();
    _recorderReady = false;
    if (mounted) setState(() => _isRecording = false);

    if (path == null || _recordSeconds < 1) {
      if (path != null)
        try {
          File(path).deleteSync();
        } catch (_) {}
      return;
    }

    final file = File(path);
    if (!await file.exists()) return;

    if (mounted) setState(() => _isSending = true);

    try {
      final success = await widget.onPushAudio(
        widget.taskId,
        file,
        widget.selectedDate,
      );
      // WS broadcast orqali provider yangilanadi, _localAudioUrl kerak emas

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Audio yuborildi' : 'Xato yuz berdi'),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(milliseconds: 800),
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

  /// Tepaga surildi → to'xtatib preview rejimiga o'tish + avtomatik eshitish
  Future<void> _stopForPreview() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    _recordTimer = null;

    final path = await _recorder.stop();
    _recorderReady = false;

    if (mounted)
      setState(() {
        _isRecording = false;
        _swipedUp = false;
      });

    if (path == null || _recordSeconds < 1) {
      if (path != null)
        try {
          File(path).deleteSync();
        } catch (_) {}
      return;
    }

    final file = File(path);
    if (!await file.exists()) return;

    if (mounted) {
      setState(() {
        _previewPath = path;
        _isPreviewCompleted = false;
        _previewPosition = Duration.zero;
        _previewDuration = Duration.zero;
      });
    }

    // Avtomatik eshitishni boshlash
    await _previewPlayer.play(DeviceFileSource(path));
  }

  /// Preview → yuborish
  Future<void> _sendPreview() async {
    final path = _previewPath;
    if (path == null) return;

    await _previewPlayer.stop();
    final file = File(path);
    if (!await file.exists()) return;

    if (mounted) setState(() => _isSending = true);

    try {
      final success = await widget.onPushAudio(
        widget.taskId,
        file,
        widget.selectedDate,
      );

      if (mounted) {
        setState(() => _previewPath = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Audio yuborildi' : 'Xato yuz berdi'),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(milliseconds: 800),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _previewPath = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xato: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Preview → o'chirish (qaytadan yozish mumkin)
  Future<void> _discardPreview() async {
    await _previewPlayer.stop();
    final path = _previewPath;
    if (path != null)
      try {
        File(path).deleteSync();
      } catch (_) {}
    if (mounted) {
      setState(() {
        _previewPath = null;
        _isPreviewPlaying = false;
        _isPreviewCompleted = false;
        _previewPosition = Duration.zero;
        _previewDuration = Duration.zero;
      });
    }
  }

  /// Preview play/pause
  Future<void> _togglePreviewPlay() async {
    if (_previewPath == null) return;
    if (_isPreviewPlaying) {
      await _previewPlayer.pause();
      return;
    }
    if (_isPreviewCompleted) {
      setState(() {
        _isPreviewCompleted = false;
        _previewPosition = Duration.zero;
      });
    }
    await _previewPlayer.play(DeviceFileSource(_previewPath!));
  }

  // ── Serverdan audio play/pause ────────────────────────────────────────────

  String? _currentPlayingUrl;

  Future<void> _togglePlay(String url) async {
    // Agar boshqa audio play qilinsa, avval to'xtatish
    if (_currentPlayingUrl != null && _currentPlayingUrl != url) {
      await _player.stop();
      setState(() {
        _isPlaying = false;
        _isCompleted = false;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }
    _currentPlayingUrl = url;

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
    if (File(url).existsSync()) {
      await _player.play(DeviceFileSource(url));
      return;
    }
    await _player.play(UrlSource(_fullAudioUrl(url)));
  }

  Future<void> _seekTo(double value) async {
    await _player.seek(
      Duration(
        milliseconds: (value.clamp(0.0, 1.0) * _duration.inMilliseconds)
            .round(),
      ),
    );
  }

  Future<void> _deleteAudio(int index) async {
    await _player.stop();
    final success = await widget.onDeleteAudio(
      widget.taskId,
      widget.selectedDate,
      index,
    );
    if (mounted) {
      setState(() {
        _currentPlayingUrl = null;
        _isPlaying = false;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }
    // WS broadcast orqali provider yangilanadi
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isSending) return _buildSending();
    if (_isRecording) return _buildRecording();
    if (_previewPath != null) return _buildPreview();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mavjud audiolar ro'yxati (har birida delete tugmasi)
        for (int i = 0; i < _audioUrls.length; i++)
          _buildAudioItem(_audioUrls[i], i),
        // Mic tugmasi (max 2 ta audio, agar 2 tadan kam bo'lsa ko'rinadi)
        if (_audioUrls.length < 2) _buildMicButton(),
      ],
    );
  }

  // ── 1. Mic tugmasi ────────────────────────────────────────────────────────

  Widget _buildMicButton() {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
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

  // ── 2. Yozilmoqda ─────────────────────────────────────────────────────────

  Widget _buildRecording() {
    return Listener(
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _swipedUp
              ? Colors.orange.withOpacity(0.12)
              : Colors.red.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _swipedUp
                ? Colors.orange.withOpacity(0.6)
                : Colors.red.withOpacity(0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulse dot
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (_swipedUp ? Colors.orange : Colors.red).withOpacity(
                    0.35 + 0.65 * _pulseCtrl.value,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _fmt(Duration(seconds: _recordSeconds)),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _swipedUp ? Colors.orange : Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            // Hint (swipe holati)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _swipedUp
                  ? const Row(
                      key: ValueKey('preview'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_upward,
                          size: 13,
                          color: Colors.orange,
                        ),
                        SizedBox(width: 2),
                        Text(
                          'Qo\'yib yuboring → tinglash',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : const Row(
                      key: ValueKey('normal'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_upward,
                          size: 13,
                          color: Colors.black38,
                        ),
                        SizedBox(width: 2),
                        Text(
                          'Tepaga — tinglash',
                          style: TextStyle(fontSize: 12, color: Colors.black45),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 3. Preview rejimi: tinglash + yuborish/o'chirish ─────────────────────

  Widget _buildPreview() {
    final double progress = (_previewDuration.inMilliseconds > 0)
        ? (_previewPosition.inMilliseconds / _previewDuration.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              'Yuborishdan oldin tinglang',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Play / Pause / Replay
              GestureDetector(
                onTap: _togglePreviewPlay,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPreviewCompleted
                        ? Icons.replay_rounded
                        : (_isPreviewPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Slider + vaqt
              SizedBox(
                width: 120,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                        activeTrackColor: Colors.orange,
                        inactiveTrackColor: Colors.black12,
                        thumbColor: Colors.orange,
                        overlayColor: Colors.orange.withOpacity(0.15),
                      ),
                      child: Slider(
                        value: progress,
                        min: 0,
                        max: 1,
                        onChanged: (v) async {
                          await _previewPlayer.seek(
                            Duration(
                              milliseconds:
                                  (v * _previewDuration.inMilliseconds).round(),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _fmt(_previewPosition),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black54,
                            ),
                          ),
                          Text(
                            _fmt(_previewDuration),
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
              const SizedBox(width: 8),
              // O'chirish (🗑)
              GestureDetector(
                onTap: _discardPreview,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.red.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Colors.red,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Yuborish (✓)
              GestureDetector(
                onTap: _sendPreview,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 4. Yuborilmoqda ───────────────────────────────────────────────────────

  Widget _buildSending() {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
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

  // ── 5. Serverdan audio player (har bir audio uchun) ──────────────────────

  Widget _buildAudioItem(String url, int index) {
    final bool isThisPlaying = _currentPlayingUrl == url;
    final double progress = isThisPlaying && _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final bool finished = isThisPlaying &&
        _duration > Duration.zero &&
        _position >= _duration;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play / Pause / Replay
            GestureDetector(
              onTap: () => _togglePlay(url),
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
                      : (isThisPlaying && _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Slider + vaqt
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
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
                      overlayColor: const Color(0xFF2196F3).withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: isThisPlaying ? progress : 0.0,
                      onChanged: isThisPlaying ? _seekTo : null,
                      min: 0,
                      max: 1,
                    ),
                  ),
                  if (isThisPlaying)
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
            // Delete tugmasi
            GestureDetector(
              onTap: () => _deleteAudio(index),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
