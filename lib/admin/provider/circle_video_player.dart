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
        // ✅ Status o'zgarganda AdminTasksProvider backenddan qayta yuklaydi
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
      if (mounted) {
        setState(() {
          _isAudioPlaying = s == PlayerState.playing;
          if (s == PlayerState.completed) {
            _isAudioCompleted = true;
            _audioPosition = Duration.zero;
          } else if (s == PlayerState.playing) {
            _isAudioCompleted = false;
          }
        });
      }
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

  // ── Audio helpers ─────────────────────────────────────────────────────────

  String? _getAudioUrl(CheckerCheckTaskModel? task) {
    return _localAudioUrl ?? task?.checkerAudioUrl;
  }

  bool _hasAudio(CheckerCheckTaskModel? task) {
    final url = _getAudioUrl(task);
    return url != null && url.isNotEmpty;
  }

  bool _canRecord(CheckerCheckTaskModel? task) {
    return task?.videoUrl != null && task!.videoUrl!.isNotEmpty;
  }

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

  Future<void> _startRecording(VideoPlayerProvider provider) async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofon ruxsati berilmagan')),
        );
      }
      return;
    }

    if (provider.isPlaying) {
      provider.togglePlayPause();
    }

    await _audioPlayer.stop();

    final task = provider.currentTask;
    if (task == null) return;

    setState(() => _isRecording = true);

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
  }

  Future<void> _stopAndSend(VideoPlayerProvider provider) async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    _recordTimer = null;

    final path = await _recorder.stop();
    setState(() => _isRecording = false);

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

    final task = provider.currentTask;
    if (task == null) return;

    setState(() => _isSending = true);

    try {
      final success = await AdminTaskService().pushAudio(
        task.taskId,
        file,
        widget.selectedDate,
      );

      if (success && mounted) {
        setState(() => _localAudioUrl = path);
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

  // ── Audio playback ────────────────────────────────────────────────────────

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

  // ── Recording signal check ────────────────────────────────────────────────

  void _checkRecordingSignal(VideoPlayerProvider provider) {
    if (provider.shouldStartRecording &&
        !_isRecording &&
        !_isSending &&
        _canRecord(provider.currentTask)) {
      provider.consumeRecordingSignal();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startRecording(provider);
      });
    }
  }

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

    _checkRecordingSignal(provider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Background tap to close ────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(color: Colors.transparent),
            ),
          ),

          // ── Main content ───────────────────────────────────────────────
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ✅ Video doirasi (text yo'q ichida)
                _buildVideoCircle(
                  context,
                  provider,
                  arcBoxSize,
                  arcRadius,
                  arcStroke,
                  circleSize,
                ),

                const SizedBox(height: 1),

                if (provider.currentTask?.task != null)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    margin: EdgeInsets.symmetric(
                      horizontal: MediaQuery.of(context).size.width * 0.1,
                      vertical: 10,
                    ),
                    child: Text(
                      provider.currentTask!.task,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                const SizedBox(height: 8),

                // ✅ Control panel (player)
                if (provider.isInitialized && !provider.hasError)
                  _buildControlPanel(provider, circleSize),
              ],
            ),
          ),

          // ── Close button ───────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),

          // ── Mute button ────────────────────────────────────────────────
          if (provider.isInitialized && !provider.hasError)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: GestureDetector(
                onTap: provider.toggleMute,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: Icon(
                    provider.isMuted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
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
          // Background arc
          CustomPaint(
            size: Size(arcBoxSize, arcBoxSize),
            painter: _CircularProgressPainter(
              progress: 1.0,
              color: Colors.white24,
              strokeWidth: arcStroke,
              radius: arcRadius,
            ),
          ),
          // Progress arc
          CustomPaint(
            size: Size(arcBoxSize, arcBoxSize),
            painter: _CircularProgressPainter(
              progress: provider.progress,
              color: Colors.blue,
              strokeWidth: arcStroke,
              radius: arcRadius,
              showDot: true,
              dotRadius: arcStroke + 5,
            ),
          ),
          // Seek gesture on arc
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
          // Video circle
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
                      if (provider.isInitialized &&
                          !provider.hasError &&
                          provider.controller != null)
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: provider.controller!.value.size.width,
                            height: provider.controller!.value.size.height,
                            child: VideoPlayer(provider.controller!),
                          ),
                        ),
                      if (!provider.isInitialized && !provider.hasError)
                        const Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      if (provider.hasError)
                        _buildErrorOverlay(provider.errorMessage),
                      // Pause overlay
                      if (provider.isInitialized && !provider.isPlaying)
                        Container(
                          color: Colors.black26,
                          child: Center(
                            child: AnimatedOpacity(
                              opacity: provider.isPlaying ? 0.0 : 1.0,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 50,
                                  color: Colors.white,
                                ),
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
              "Video yuklanmadi",
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

  // ── Control panel ─────────────────────────────────────────────────────────

  Widget _buildControlPanel(VideoPlayerProvider provider, double circleSize) {
    return Container(
      width: circleSize,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTimeRow(provider),
          const SizedBox(height: 4),
          if (_isRecording)
            _buildRecordingRow(provider)
          else if (_isSending)
            _buildSendingRow()
          else
            _buildControlsRow(provider),
        ],
      ),
    );
  }

  Widget _buildTimeRow(VideoPlayerProvider provider) {
    final task = provider.currentTask;
    return Row(
      children: [
        Text(
          "${task?.date ?? ''} "
          "${task?.submittedAt?.toLocal().hour.toString().padLeft(2, '0') ?? '00'}:"
          "${task?.submittedAt?.toLocal().minute.toString().padLeft(2, '0') ?? '00'}",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (provider.videoUrls.length > 1)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '${provider.currentIndex + 1}/${provider.videoUrls.length}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        Text(
          provider.formatDuration(provider.duration),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildControlsRow(VideoPlayerProvider provider) {
    final task = provider.currentTask;

    return Row(
      children: [
        Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: provider.hasPrev ? provider.goToPrev : null,
          icon: Icon(
            Icons.skip_previous_rounded,
            color: provider.hasPrev ? Colors.white : Colors.white30,
            size: 28,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: provider.togglePlayPause,
          icon: Icon(
            provider.isPlaying
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_filled_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: provider.hasNext ? provider.goToNext : null,
          icon: Icon(
            Icons.skip_next_rounded,
            color: provider.hasNext ? Colors.white : Colors.white30,
            size: 28,
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: provider.cycleSpeed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: provider.playbackSpeed != 1.0
                  ? Colors.blue.withOpacity(0.8)
                  : Colors.white24,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              provider.speedLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        const Spacer(),

        if (_hasAudio(task))
          _buildMiniAudioPlayer(task)
        else if (_canRecord(task))
          GestureDetector(
            onTap: () => _startRecording(provider),
            child: Container(
              width: 45,
              height: 45,
              decoration: const BoxDecoration(
                color: Colors.white24,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_rounded,
                size: 25,
                color: Colors.white,
              ),
            ),
          ),

        const SizedBox(width: 20),

        if (task != null) _buildStatusIndicator(provider, task),
      ],
    );
  }

  Widget _buildMiniAudioPlayer(CheckerCheckTaskModel? task) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _toggleAudioPlay(task),
          child: Container(
            width: 30,
            height: 30,
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
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 40,
          child: Text(
            _isAudioPlaying || _audioPosition > Duration.zero
                ? _fmt(_audioPosition)
                : _fmt(_audioDuration),
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ),
        if (_canRecord(task))
          GestureDetector(
            onTap: () => _startRecording(context.read<VideoPlayerProvider>()),
            child: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.mic_rounded, size: 16, color: Colors.white54),
            ),
          ),
      ],
    );
  }

  Widget _buildRecordingRow(VideoPlayerProvider provider) {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => Container(
            width: 12,
            height: 12,
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
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.red,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Yozilmoqda...',
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ),
        GestureDetector(
          onTap: _cancelRecording,
          child: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.delete_outline,
              size: 25,
              color: Colors.white70,
            ),
          ),
        ),
        const SizedBox(width: 32),
        GestureDetector(
          onTap: () => _stopAndSend(provider),
          child: Container(
            width: 45,
            height: 45,
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
    );
  }

  Widget _buildSendingRow() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
        SizedBox(width: 10),
        Text(
          'Yuborilmoqda...',
          style: TextStyle(fontSize: 13, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildStatusIndicator(
    VideoPlayerProvider provider,
    CheckerCheckTaskModel task,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _statusCircleButton(provider, task, 3, Colors.green),
        const SizedBox(width: 25),
        _statusCircleButton(provider, task, 2, Colors.orange),
        const SizedBox(width: 25),
        _statusCircleButton(provider, task, 1, Colors.red),
      ],
    );
  }

  Widget _statusCircleButton(
    VideoPlayerProvider provider,
    CheckerCheckTaskModel task,
    int level,
    Color activeColor,
  ) {
    final bool isActive = task.status >= level;

    return GestureDetector(
      onTap: () async {
        if (task.status != level) {
          await provider.updateTaskStatus(task.taskId, level, task.date);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 35,
        height: 35,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? activeColor : Colors.grey.shade300,
          border: Border.all(
            color: isActive ? activeColor : Colors.grey,
            width: 2,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: activeColor.withOpacity(0.4), blurRadius: 4)]
              : [],
        ),
        child: isActive
            ? const Icon(Icons.check, size: 20, color: Colors.white)
            : null,
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
