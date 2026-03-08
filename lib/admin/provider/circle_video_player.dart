import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/video_player_provider.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

class CircleVideoPlayer extends StatelessWidget {
  final List<CheckerCheckTaskModel> title;
  final List<String> videoUrls;
  final int initialIndex;
  final VoidCallback? onHalfWatched;
  final DateTime selectedDate;

  const CircleVideoPlayer({
    required this.title,
    super.key,
    required this.videoUrls,
    this.initialIndex = 0,
    this.onHalfWatched,
    required this.selectedDate,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => VideoPlayerProvider(
        videoUrls: videoUrls,
        tasks: title,
        initialIndex: initialIndex,
        onHalfWatched: onHalfWatched,
        onStatusChanged: () {
          try {
            context.read<AdminTasksProvider>().fetchTasks();
          } catch (_) {}
        },
      ),
      child: _CircleVideoPlayerBody(selectedDate: selectedDate),
    );
  }
}

class _CircleVideoPlayerBody extends StatefulWidget {
  final DateTime selectedDate;
  const _CircleVideoPlayerBody({required this.selectedDate});

  @override
  State<_CircleVideoPlayerBody> createState() => _CircleVideoPlayerBodyState();
}

class _CircleVideoPlayerBodyState extends State<_CircleVideoPlayerBody>
    with TickerProviderStateMixin {
  late AnimationController _animationController;

  // ── Audio Recording ───────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isSending = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  late AnimationController _pulseCtrl;

  // ── Audio Player ──────────────────────────────────────────────────────────
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioPlaying = false;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  bool _isAudioCompleted = false;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;

  String? _localAudioUrl;

  // ── Status button Listener ────────────────────────────────────────────────
  int? _pressedLevel;
  int? _lastPressedLevel; // audio yuborilgandan keyin status uchun
  bool _pressedInside = true;

  final Map<int, GlobalKey> _statusKeys = {
    1: GlobalKey(),
    2: GlobalKey(),
    3: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() {
        _isAudioPlaying = s == PlayerState.playing;
        if (s == PlayerState.completed) {
          _isAudioCompleted = true;
          _audioPosition = Duration.zero;
        } else if (s == PlayerState.playing) {
          _isAudioCompleted = false;
        }
      });
    });
    _positionSub = _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _audioPosition = p);
    });
    _durationSub = _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _audioDuration = d);
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseCtrl.dispose();
    _recorder.dispose();
    _audioPlayer.dispose();
    _recordTimer?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }

  // ── Responsive ────────────────────────────────────────────────────────────

  bool get _isTablet => MediaQuery.of(context).size.shortestSide >= 600;
  double get _iconSizeLarge => _isTablet ? 50.0 : 38.0;
  double get _circleButtonSize => _isTablet ? 45.0 : 34.0;
  double get _statusCircleSize => _isTablet ? 55.0 : 26.0;
  double get _statusIconSize => _isTablet ? 20.0 : 15.0;
  double get _audioPlayButtonSize => _isTablet ? 30.0 : 24.0;
  double get _audioPlayIconSize => _isTablet ? 18.0 : 14.0;
  double get _audioMicIconSize => _isTablet ? 16.0 : 12.0;
  double get _audioTimeWidth => _isTablet ? 40.0 : 32.0;
  double get _audioTimeFontSize => _isTablet ? 10.0 : 8.5;
  double get _timeFontSize => _isTablet ? 30.0 : 11.0;
  double get _indexFontSize => _isTablet ? 12.0 : 10.0;
  double get _statusGap => _isTablet ? 25.0 : 10.0;
  double get _recordingFontSize => _isTablet ? 16.0 : 13.0;
  double get _recordingSubFontSize => _isTablet ? 13.0 : 11.0;
  double get _pulseDotSize => _isTablet ? 12.0 : 9.0;
  double get _sendIconSize => _isTablet ? 18.0 : 14.0;
  double get _bottomButtonRadius => _isTablet ? 40.0 : 16.0;
  double get _bottomIconSize => _isTablet ? 48.0 : 18.0;

  // ── Share ─────────────────────────────────────────────────────────────────

  final GlobalKey _shareButtonKey = GlobalKey();

  void _shareTaskLink(
    BuildContext context,
    VideoPlayerProvider provider,
    CheckerCheckTaskModel? task,
  ) {
    if (task == null) return;
    if (provider.isPlaying) provider.togglePlayPause();

    final link = 'https://monebakeryuz.uz/${task.date}/${task.taskId}';
    final box =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final Rect sharePosition;
    if (box != null) {
      final pos = box.localToGlobal(Offset.zero);
      sharePosition = Rect.fromLTWH(
        pos.dx,
        pos.dy,
        box.size.width,
        box.size.height,
      );
    } else {
      final size = MediaQuery.of(context).size;
      sharePosition = Rect.fromLTWH(
        size.width - 100,
        size.height - 100,
        100,
        100,
      );
    }
    Share.share(
      '${task.task}\n$link',
      subject: task.task,
      sharePositionOrigin: sharePosition,
    );
  }

  // ── Audio helpers ─────────────────────────────────────────────────────────

  String? _getAudioUrl(CheckerCheckTaskModel? task) =>
      _localAudioUrl ?? task?.checkerAudioUrl;

  bool _hasAudio(CheckerCheckTaskModel? task) {
    final url = _getAudioUrl(task);
    return url != null && url.isNotEmpty;
  }

  bool _canRecord(CheckerCheckTaskModel? task) =>
      task?.videoUrl != null && task!.videoUrl!.isNotEmpty;

  String _fullAudioUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '${AppUrls.baseUrl}/$url';
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Recording actions ─────────────────────────────────────────────────────

  Future<bool> _startRecording(VideoPlayerProvider provider) async {
    if (_isRecording || _isSending) return false;

    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofon ruxsati berilmagan')),
        );
      }
      return false;
    }

    final task = provider.currentTask;
    if (task == null) return false;

    if (provider.isPlaying) provider.togglePlayPause();
    await _audioPlayer.stop();

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${task.taskId}_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: path,
    );

    _recordSeconds = 0;
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });

    if (mounted) setState(() => _isRecording = true);
    return true;
  }

  Future<void> _stopAndSend(
    VideoPlayerProvider provider, {
    bool goNext = false,
  }) async {
    if (!_isRecording) return;

    _recordTimer?.cancel();
    _recordTimer = null;

    final path = await _recorder.stop();
    if (mounted) setState(() => _isRecording = false);

    if (path == null) return;

    final file = File(path);
    if (!await file.exists() || await file.length() < 100) {
      try {
        file.deleteSync();
      } catch (_) {}
      return;
    }

    final task = provider.currentTask;
    if (task == null) return;

    if (mounted) setState(() => _isSending = true);

    try {
      final success = await AdminTaskService().pushAudio(
        task.taskId,
        file,
        widget.selectedDate,
      );

      if (success && mounted) {
        setState(() => _localAudioUrl = path);

        // ✅ Faqat audio muvaffaqiyatli yuborilgandan KEYIN status yangilanadi
        if (_lastPressedLevel != null) {
          await provider.updateTaskStatus(
            task.taskId,
            _lastPressedLevel!,
            task.date,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Audio yuborildi ✓' : 'Xato yuz berdi'),
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

    // goNext: false — video o'z-o'zidan o'tmaydi
    if (goNext && provider.hasNext && mounted) {
      _localAudioUrl = null;
      provider.goToNext();
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    _recordTimer = null;
    await _recorder.stop();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _lastPressedLevel = null;
      });
    }
  }

  Future<void> _toggleAudioPlay(CheckerCheckTaskModel? task) async {
    final audioUrl = _getAudioUrl(task);
    if (audioUrl == null) return;

    if (_isAudioPlaying) {
      await _audioPlayer.pause();
      return;
    }

    if (_isAudioCompleted) {
      setState(() {
        _isAudioCompleted = false;
        _audioPosition = Duration.zero;
      });
    }

    if (_localAudioUrl != null && File(_localAudioUrl!).existsSync()) {
      await _audioPlayer.play(DeviceFileSource(_localAudioUrl!));
      return;
    }
    await _audioPlayer.play(UrlSource(_fullAudioUrl(audioUrl)));
  }

  // ── Status Listener callbacks ─────────────────────────────────────────────

  bool _isInsideButton(int level, Offset globalPos) {
    final box =
        _statusKeys[level]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final local = box.globalToLocal(globalPos);
    return local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx <= box.size.width &&
        local.dy <= box.size.height;
  }

  Future<void> _onStatusPointerDown(
    PointerDownEvent event,
    VideoPlayerProvider provider,
    CheckerCheckTaskModel task,
  ) async {
    int? tappedLevel;
    for (final level in [1, 2, 3]) {
      if (_isInsideButton(level, event.position)) {
        tappedLevel = level;
        break;
      }
    }
    if (tappedLevel == null) return;

    setState(() {
      _pressedLevel = tappedLevel;
      _lastPressedLevel = tappedLevel; // ✅ keyinroq status uchun saqlaymiz
      _pressedInside = true;
    });

    // ✅ Status 3 (yashil) — audio yo'q, darhol yangilansin
    if (tappedLevel == 3) {
      provider.updateTaskStatus(task.taskId, tappedLevel, task.date);
      return;
    }

    // ✅ Status 1 va 2 — avval audio yoziladi, status KEYIN o'zgaradi
    if (!_isRecording && !_isSending) {
      await _startRecording(provider);
    }
  }

  void _onStatusPointerMove(PointerMoveEvent event) {
    if (_pressedLevel == null || _pressedLevel == 3) return;
    final inside = _isInsideButton(_pressedLevel!, event.position);
    if (inside != _pressedInside) {
      setState(() => _pressedInside = inside);
    }
  }

  Future<void> _onStatusPointerUp(
    PointerUpEvent event,
    VideoPlayerProvider provider,
  ) async {
    final level = _pressedLevel;
    final inside = _pressedInside;
    setState(() {
      _pressedLevel = null;
      _pressedInside = true;
    });

    if (level == null || level == 3) return;
    if (!_isRecording) return;

    if (inside) {
      // ✅ goNext: false — audio yuborilgandan keyin video o'tmaydi
      await _stopAndSend(provider, goNext: false);
    }
    // Tashqarida qo'yildi → manual send/delete ko'rinadi
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VideoPlayerProvider>();
    final size = MediaQuery.of(context).size;
    final bool isTablet = size.shortestSide >= 600;

    final double circleSize = isTablet
        ? size.shortestSide * 0.7
        : size.width * 0.85;
    final double arcRadius = circleSize / 2 + 20;
    final double arcStroke = 8.0;
    final double arcBoxSize = (arcRadius + arcStroke) * 2;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Prev ──────────────────────────────────────────────────────
          Positioned(
            right: arcBoxSize * 0.25,
            bottom: arcBoxSize * 0.25,
            child: GestureDetector(
              onTap: provider.hasPrev ? provider.goToPrev : null,
              child: AnimatedOpacity(
                opacity: provider.hasPrev ? 1.0 : 0.25,
                duration: const Duration(milliseconds: 200),
                child: CircleAvatar(
                  radius: _bottomButtonRadius,
                  backgroundColor: Colors.black.withOpacity(0.75),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: _bottomIconSize,
                  ),
                ),
              ),
            ),
          ),
          // ── Next ──────────────────────────────────────────────────────
          Positioned(
            right: arcBoxSize * 0.05,
            bottom: arcBoxSize * 0.25,
            child: GestureDetector(
              onTap: provider.hasNext ? provider.goToNext : null,
              child: AnimatedOpacity(
                opacity: provider.hasNext ? 1.0 : 0.25,
                duration: const Duration(milliseconds: 200),
                child: CircleAvatar(
                  radius: _bottomButtonRadius,
                  backgroundColor: Colors.black.withOpacity(0.75),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white,
                    size: _bottomIconSize,
                  ),
                ),
              ),
            ),
          ),

          // ── Markaziy kontent ──────────────────────────────────────────
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTimeRow(provider),
                _buildVideoCircle(
                  context,
                  provider,
                  arcBoxSize,
                  arcRadius,
                  arcStroke,
                  circleSize,
                ),
                if (provider.currentTask?.task != null)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    margin: EdgeInsets.symmetric(
                      horizontal: size.width * 0.1,
                      vertical: 10,
                    ),
                    child: Text(
                      provider.currentTask!.task,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: isTablet ? 18 : 14,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),

          // ── Boshqaruv paneli (audio + status) — video ustida ──────────
          if (provider.isInitialized && !provider.hasError)
            Positioned(
              right: 20,
              top: 200,
              bottom: 0,
              child: Center(child: _buildControlPanel(provider)),
            ),

          // ── Quyi qator ────────────────────────────────────────────────
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                if (provider.isInitialized && !provider.hasError) ...[
                  GestureDetector(
                    onTap: provider.toggleMute,
                    child: CircleAvatar(
                      radius: _bottomButtonRadius,
                      backgroundColor: Colors.black54,
                      child: Icon(
                        provider.isMuted ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                        size: _bottomIconSize,
                      ),
                    ),
                  ),
                  SizedBox(width: _isTablet ? 20 : 10),
                  GestureDetector(
                    onTap: provider.cycleSpeed,
                    child: CircleAvatar(
                      radius: _bottomButtonRadius,
                      backgroundColor: provider.playbackSpeed != 1.0
                          ? Colors.blue.withOpacity(0.8)
                          : Colors.black54,
                      child: Text(
                        provider.speedLabel,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _isTablet ? 16 : 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                GestureDetector(
                  key: _shareButtonKey,
                  onTap: () =>
                      _shareTaskLink(context, provider, provider.currentTask),
                  child: CircleAvatar(
                    radius: _bottomButtonRadius,
                    backgroundColor: Colors.black54,
                    child: Icon(
                      Icons.share_rounded,
                      color: Colors.white,
                      size: _bottomIconSize,
                    ),
                  ),
                ),
                SizedBox(width: _isTablet ? 20 : 10),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: CircleAvatar(
                    radius: _bottomButtonRadius,
                    backgroundColor: Colors.black54,
                    child: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: _bottomIconSize,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Time row ──────────────────────────────────────────────────────────────

  Widget _buildTimeRow(VideoPlayerProvider provider) {
    if (_isRecording || _isSending) return const SizedBox.shrink();

    final task = provider.currentTask;
    return Row(
      children: [
        Text(
          '   ${task?.submittedAt?.toLocal().hour.toString().padLeft(2, '0') ?? '00'}:'
          '${task?.submittedAt?.toLocal().minute.toString().padLeft(2, '0') ?? '00'}   '
          '${task?.date ?? ''}',
          style: TextStyle(
            color: Colors.black,
            fontSize: _timeFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (provider.videoUrls.length > 1)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '${provider.currentIndex + 1}/${provider.videoUrls.length}',
              style: TextStyle(color: Colors.white54, fontSize: _indexFontSize),
            ),
          ),
        Text(
          provider.formatDuration(provider.duration),
          style: TextStyle(color: Colors.white70, fontSize: _timeFontSize),
        ),
      ],
    );
  }

  // ── Control panel ─────────────────────────────────────────────────────────

  Widget _buildControlPanel(VideoPlayerProvider provider) {
    final task = provider.currentTask;
    if (task == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isTablet ? 16 : 12,
        vertical: _isTablet ? 10 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.60),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_isRecording)
            _buildRecordingRow(provider)
          else if (_isSending)
            _buildSendingRow()
          else if (_hasAudio(task))
            _buildMiniAudioPlayer(task, provider)
          else if (_canRecord(task))
            GestureDetector(
              onTap: () => _startRecording(provider),
              child: Container(
                width: _circleButtonSize,
                height: _circleButtonSize,
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mic_rounded,
                  size: _isTablet ? 25 : 18,
                  color: Colors.white,
                ),
              ),
            ),

          if (!_isRecording && !_isSending)
            SizedBox(height: _isTablet ? 10 : 7),

          if (!_isRecording && !_isSending)
            _buildStatusIndicator(provider, task),
        ],
      ),
    );
  }

  // ── Mini audio player ─────────────────────────────────────────────────────

  Widget _buildMiniAudioPlayer(
    CheckerCheckTaskModel? task,
    VideoPlayerProvider provider,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _toggleAudioPlay(task),
          child: Container(
            width: _audioPlayButtonSize,
            height: _audioPlayButtonSize,
            decoration: const BoxDecoration(
              color: Color(0xFF2196F3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isAudioCompleted
                  ? Icons.replay_rounded
                  : (_isAudioPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
              color: Colors.white,
              size: _audioPlayIconSize,
            ),
          ),
        ),
        SizedBox(width: _isTablet ? 6 : 4),
        SizedBox(
          width: _audioTimeWidth,
          child: Text(
            _isAudioPlaying || _audioPosition > Duration.zero
                ? _fmt(_audioPosition)
                : _fmt(_audioDuration),
            style: TextStyle(
              color: Colors.white70,
              fontSize: _audioTimeFontSize,
            ),
          ),
        ),
        if (_canRecord(task))
          GestureDetector(
            onTap: () => _startRecording(provider),
            child: Padding(
              padding: EdgeInsets.only(left: _isTablet ? 4 : 2),
              child: Icon(
                Icons.mic_rounded,
                size: _audioMicIconSize,
                color: Colors.white54,
              ),
            ),
          ),
      ],
    );
  }

  // ── Recording row ─────────────────────────────────────────────────────────

  Widget _buildRecordingRow(VideoPlayerProvider provider) {
    final bool showManualControls = _pressedLevel == null && _isRecording;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => Container(
            width: _pulseDotSize,
            height: _pulseDotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withOpacity(0.35 + 0.65 * _pulseCtrl.value),
            ),
          ),
        ),
        SizedBox(width: _isTablet ? 16 : 5),
        Text(
          _fmt(Duration(seconds: _recordSeconds)),
          style: TextStyle(
            fontSize: _recordingFontSize,
            fontWeight: FontWeight.w600,
            color: Colors.red,
          ),
        ),
        SizedBox(width: _isTablet ? 8 : 5),

        if (showManualControls) ...[
          SizedBox(width: _isTablet ? 12 : 8),
          // Bekor qilish
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              width: _circleButtonSize,
              height: _circleButtonSize,
              decoration: const BoxDecoration(
                color: Colors.white24,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_outline,
                size: _isTablet ? 25 : 18,
                color: Colors.white70,
              ),
            ),
          ),
          SizedBox(width: _isTablet ? 16 : 8),
          // Yuborish — goNext: false
          GestureDetector(
            onTap: () => _stopAndSend(provider, goNext: false),
            child: Container(
              width: _circleButtonSize,
              height: _circleButtonSize,
              decoration: const BoxDecoration(
                color: Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.send_rounded,
                size: _sendIconSize,
                color: Colors.white,
              ),
            ),
          ),
        ] else ...[
          SizedBox(width: _isTablet ? 8 : 4),
          Text(
            _pressedInside ? 'Qo\'yib yuboring →' : '↑ Tepaga — davom etadi',
            style: TextStyle(
              fontSize: _recordingSubFontSize,
              color: _pressedInside ? Colors.white70 : Colors.orange,
            ),
          ),
        ],
      ],
    );
  }

  // ── Sending row ───────────────────────────────────────────────────────────

  Widget _buildSendingRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _isTablet ? 18 : 14,
          height: _isTablet ? 18 : 14,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Yuborilmoqda...',
          style: TextStyle(
            fontSize: _recordingSubFontSize,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  // ── Status indicator ──────────────────────────────────────────────────────

  Widget _buildStatusIndicator(
    VideoPlayerProvider provider,
    CheckerCheckTaskModel task,
  ) {
    return Listener(
      onPointerDown: (e) => _onStatusPointerDown(e, provider, task),
      onPointerMove: _onStatusPointerMove,
      onPointerUp: (e) => _onStatusPointerUp(e, provider),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusCircle(task, 3, Colors.green),
          SizedBox(width: _statusGap),
          _statusCircle(task, 2, Colors.orange),
          SizedBox(width: _statusGap),
          _statusCircle(task, 1, Colors.red),
        ],
      ),
    );
  }

  Widget _statusCircle(
    CheckerCheckTaskModel task,
    int level,
    Color activeColor,
  ) {
    final bool isActive = task.status == level;
    final bool isHolding = _pressedLevel == level;

    return Container(
      key: _statusKeys[level],
      width: isHolding ? _statusCircleSize + 6 : _statusCircleSize,
      height: isHolding ? _statusCircleSize + 6 : _statusCircleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isHolding
            ? activeColor
            : isActive
            ? activeColor
            : activeColor.withOpacity(0.2), // ← past rang
        border: Border.all(
          color: isHolding
              ? activeColor
              : isActive
              ? activeColor
              : activeColor.withOpacity(0.9), // ← past chegara
          width: isHolding ? 3 : 2,
        ),
        boxShadow: isActive || isHolding
            ? [
                BoxShadow(
                  color: activeColor.withOpacity(0.4),
                  blurRadius: isHolding ? 8 : 4,
                ),
              ]
            : [],
      ),
      child: isActive
          ? Icon(Icons.check, size: _statusIconSize, color: Colors.white)
          : (level != 3
                ? Icon(
                    Icons.mic_rounded,
                    size: _statusIconSize - 2,
                    color: Colors.white, // ← mic ham rangli
                  )
                : null),
    );
  }
  // ── Video circle ──────────────────────────────────────────────────────────

  Widget _buildVideoCircle(
    BuildContext context,
    VideoPlayerProvider provider,
    double arcBoxSize,
    double arcRadius,
    double arcStroke,
    double circleSize,
  ) {
    return SizedBox(
      width: arcBoxSize,
      height: arcBoxSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(arcBoxSize, arcBoxSize),
            painter: _CircularProgressPainter(
              progress: 1.0,
              color: Colors.grey.shade300,
              strokeWidth: arcStroke,
              radius: arcRadius,
            ),
          ),
          CustomPaint(
            size: Size(arcBoxSize, arcBoxSize),
            painter: _CircularProgressPainter(
              progress: provider.progress,
              color: Colors.blue,
              strokeWidth: arcStroke,
              radius: arcRadius,
              showDot: true,
              dotRadius: arcStroke + 10,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: provider.isInitialized
                ? (d) =>
                      provider.seekFromCircleTouch(d.localPosition, arcBoxSize)
                : null,
            onPanUpdate: provider.isInitialized
                ? (d) =>
                      provider.seekFromCircleTouch(d.localPosition, arcBoxSize)
                : null,
            onTapDown: provider.isInitialized
                ? (d) =>
                      provider.seekFromCircleTouch(d.localPosition, arcBoxSize)
                : null,
            child: SizedBox(width: arcBoxSize, height: arcBoxSize),
          ),
          ScaleTransition(
            scale: Tween(begin: 0.8, end: 1.0).animate(
              CurvedAnimation(
                parent: _animationController,
                curve: Curves.easeOut,
              ),
            ),
            child: GestureDetector(
              onTap: provider.isInitialized ? provider.togglePlayPause : null,
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity != null) {
                  if (details.primaryVelocity! < -300) provider.goToNext();
                  if (details.primaryVelocity! > 300) provider.goToPrev();
                }
              },
              child: Container(
                width: circleSize,
                height: circleSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // ✅ Race condition fix: ctrl o'zgaruvchisiga olamiz
                      Builder(
                        builder: (context) {
                          final ctrl = provider.controller;
                          if (!provider.isInitialized ||
                              provider.hasError ||
                              ctrl == null) {
                            return const SizedBox.shrink();
                          }
                          return FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: ctrl.value.size.width,
                              height: ctrl.value.size.height,
                              child: VideoPlayer(ctrl),
                            ),
                          );
                        },
                      ),
                      if (!provider.isInitialized && !provider.hasError)
                        const Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      if (provider.hasError)
                        _buildErrorOverlay(provider.errorMessage),
                      if (provider.isInitialized && !provider.isPlaying)
                        Container(
                          color: Colors.black26,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.play_arrow_rounded,
                                size: _iconSizeLarge,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorOverlay(String? errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Video yuklanmadi',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                errorMessage,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Circular progress painter ──────────────────────────────────────────────

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final double radius;
  final bool showDot;
  final double dotRadius;

  const _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.radius,
    this.showDot = false,
    this.dotRadius = 9,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );

    if (showDot && progress > 0) {
      final dotAngle = startAngle + sweepAngle;
      final dotX = center.dx + radius * math.cos(dotAngle);
      final dotY = center.dy + radius * math.sin(dotAngle);
      canvas.drawCircle(
        Offset(dotX, dotY),
        dotRadius,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(dotX, dotY),
        dotRadius - 3,
        Paint()..color = Colors.blue,
      );
    }
  }

  @override
  bool shouldRepaint(_CircularProgressPainter old) =>
      old.progress != progress || old.color != color;
}
