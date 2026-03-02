import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class CircleVideoPlayer extends StatefulWidget {
  final List<CheckerCheckTaskModel> title;

  final List<String> videoUrls;
  final int initialIndex;
  final VoidCallback? onHalfWatched;

  const CircleVideoPlayer({
    required this.title,
    super.key,
    required this.videoUrls,
    this.initialIndex = 0,
    this.onHalfWatched,
  });

  @override
  State<CircleVideoPlayer> createState() => _CircleVideoPlayerState();
}

class _CircleVideoPlayerState extends State<CircleVideoPlayer>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _halfWatchedFired = false;
  late int _currentIndex;

  bool _isActiveVideo = false;
  bool _isMuted = false;
  double _playbackSpeed = 1.0;
  static const List<double> _speedOptions = [1.0, 1.5, 2.0];

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    WakelockPlus.enable();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _initializeVideo();
  }

  String get _currentUrl => widget.videoUrls[_currentIndex];
  bool get _hasPrev => _currentIndex > 0;
  bool get _hasNext => _currentIndex < widget.videoUrls.length - 1;

  Future<void> _initializeVideo() async {
    if (_isActiveVideo) return;
    _isActiveVideo = true;

    if (_isInitialized) {
      _controller.removeListener(_onVideoListener);
      await _controller.dispose();
    }

    setState(() {
      _isInitialized = false;
      _hasError = false;
      _errorMessage = null;
      _halfWatchedFired = false;
    });

    try {
      String videoPath = _currentUrl;

      if (videoPath.contains('://') && videoPath.contains('/Users/')) {
        final m = RegExp(r'/Users/.*').firstMatch(videoPath);
        if (m != null) videoPath = m.group(0)!;
      } else if (videoPath.contains('://') && videoPath.contains('/data/')) {
        final m = RegExp(r'/data/.*').firstMatch(videoPath);
        if (m != null) videoPath = m.group(0)!;
      }

      bool isLocal =
          !videoPath.startsWith('http://') && !videoPath.startsWith('https://');

      if (isLocal) {
        final file = File(videoPath);
        if (!await file.exists()) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Fayl topilmadi: $videoPath';
            _isActiveVideo = false;
          });
          return;
        }
        if (await file.length() == 0) {
          setState(() {
            _hasError = true;
            _errorMessage = "Video fayl bo'sh";
            _isActiveVideo = false;
          });
          return;
        }
        _controller = VideoPlayerController.file(file);
      } else {
        _controller = VideoPlayerController.networkUrl(Uri.parse(videoPath));
      }

      await _controller.initialize();
      await _controller.setLooping(false);
      await _controller.setVolume(_isMuted ? 0.0 : 1.0);
      await _controller.setPlaybackSpeed(_playbackSpeed);
      await _controller.play();

      _controller.addListener(_onVideoListener);

      setState(() {
        _isInitialized = true;
        _isPlaying = true;
        _isActiveVideo = false;
      });

      _animationController.reset();
      _animationController.forward();
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
        _isActiveVideo = false;
      });
    }
  }

  void _onVideoListener() {
    if (!mounted) return;
    setState(() {});

    final value = _controller.value;
    if (!value.isInitialized) return;

    final total = value.duration.inMilliseconds;
    final current = value.position.inMilliseconds;

    if (!_halfWatchedFired && total > 0 && current >= total * 0.5) {
      _halfWatchedFired = true;
      widget.onHalfWatched?.call();
    }

    if (!value.isPlaying && current >= total - 200) {
      _goToNext();
    }
  }

  void _goToNext() {
    if (_hasNext) {
      setState(() => _currentIndex++);
      _isActiveVideo = false;
      _initializeVideo();
    }
  }

  void _goToPrev() {
    if (_hasPrev) {
      setState(() => _currentIndex--);
      _isActiveVideo = false;
      _initializeVideo();
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      if (_isInitialized) _controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _cycleSpeed() {
    final nextIdx =
        (_speedOptions.indexOf(_playbackSpeed) + 1) % _speedOptions.length;
    setState(() {
      _playbackSpeed = _speedOptions[nextIdx];
      if (_isInitialized) _controller.setPlaybackSpeed(_playbackSpeed);
    });
  }

  /// Doira ustida bosilgan nuqtadan pozitsiyani hisoblash
  void _seekFromCircleTouch(Offset localPos, double circleSize) {
    final center = Offset(circleSize / 2, circleSize / 2);
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;

    // Burchak: yuqoridan soat yo'nalishida (-pi/2 offset)
    double angle = math.atan2(dy, dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    final ratio = angle / (2 * math.pi);
    final duration = _controller.value.duration;
    _controller.seekTo(duration * ratio);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    if (_isInitialized) {
      _controller.removeListener(_onVideoListener);
      _controller.dispose();
    }
    _animationController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  String get _speedLabel {
    if (_playbackSpeed == 1.0) return 'x1';
    if (_playbackSpeed == 1.5) return 'x1.5';
    return 'x2';
  }

  /// Vaqt ko'rsatadigan kichik widget — doira tagida
  Widget _buildTimeRow() {
    final duration = _controller.value.duration;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (widget.videoUrls.length > 1)
          Text(
            '${_currentIndex + 1} / ${widget.videoUrls.length}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        Text(
          _formatDuration(duration),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }

  /// Boshqaruv tugmalari
  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: _hasPrev ? _goToPrev : null,
          icon: Icon(
            Icons.skip_previous_rounded,
            color: _hasPrev ? Colors.white : Colors.white30,
            size: 32,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () {
            setState(() {
              _isPlaying ? _controller.pause() : _controller.play();
              _isPlaying = !_isPlaying;
            });
          },
          icon: Icon(
            _isPlaying
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_filled_rounded,
            color: Colors.white,
            size: 44,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: _hasNext ? _goToNext : null,
          icon: Icon(
            Icons.skip_next_rounded,
            color: _hasNext ? Colors.white : Colors.white30,
            size: 32,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _cycleSpeed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _playbackSpeed != 1.0
                  ? Colors.blue.withOpacity(0.8)
                  : Colors.white24,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _speedLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isTablet = size.shortestSide >= 600;
    final double circleSize = isTablet
        ? size.shortestSide * 0.70
        : size.width * 0.85;

    // Progress doirasi uchun radius — video doirasidan biroz tashqarida
    final double arcRadius = circleSize / 2 + 14;
    final double arcStroke = 6.0;
    final double arcBoxSize = (arcRadius + arcStroke) * 2;

    double progress = 0.0;
    if (_isInitialized && !_hasError) {
      final total = _controller.value.duration.inMilliseconds;
      final current = _controller.value.position.inMilliseconds;
      if (total > 0) progress = (current / total).clamp(0.0, 1.0);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: MediaQuery.of(context).size.width == 600 ? 16 : 50,
            right: MediaQuery.of(context).size.width == 600 ? 16 : 50,
            child: Text(
              widget.title.isNotEmpty
                  ? widget.title[_currentIndex].task
                  : "Видео",
              style: const TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Tashqariga bosganda yopish
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(color: Colors.transparent),
            ),
          ),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Video doirasi + progress arc ──────────────────────────
                SizedBox(
                  width: arcBoxSize,
                  height: arcBoxSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1. Progress arc (orqa — kulrang)
                      CustomPaint(
                        size: Size(arcBoxSize, arcBoxSize),
                        painter: _CircularProgressPainter(
                          progress: 1.0,
                          color: Colors.white24,
                          strokeWidth: arcStroke,
                          radius: arcRadius,
                        ),
                      ),
                      // 2. Progress arc (oldi — ko'k)
                      CustomPaint(
                        size: Size(arcBoxSize, arcBoxSize),
                        painter: _CircularProgressPainter(
                          progress: progress,
                          color: Colors.blue,
                          strokeWidth: arcStroke,
                          radius: arcRadius,
                          showDot: true,
                        ),
                      ),
                      // 3. Arc ustiga bosilganda seek qilish
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: _isInitialized
                            ? (d) => _seekFromCircleTouch(
                                d.localPosition,
                                arcBoxSize,
                              )
                            : null,
                        onPanUpdate: _isInitialized
                            ? (d) => _seekFromCircleTouch(
                                d.localPosition,
                                arcBoxSize,
                              )
                            : null,
                        onTapDown: _isInitialized
                            ? (d) => _seekFromCircleTouch(
                                d.localPosition,
                                arcBoxSize,
                              )
                            : null,
                        child: SizedBox(width: arcBoxSize, height: arcBoxSize),
                      ),
                      // 4. Video doirasi (markazda)
                      ScaleTransition(
                        scale: Tween(begin: 0.8, end: 1.0).animate(
                          CurvedAnimation(
                            parent: _animationController,
                            curve: Curves.easeOut,
                          ),
                        ),
                        child: GestureDetector(
                          onHorizontalDragEnd: (details) {
                            if (details.primaryVelocity != null) {
                              if (details.primaryVelocity! < -300) _goToNext();
                              if (details.primaryVelocity! > 300) _goToPrev();
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
                                  if (_isInitialized && !_hasError)
                                    FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: _controller.value.size.width,
                                        height: _controller.value.size.height,
                                        child: VideoPlayer(_controller),
                                      ),
                                    ),
                                  if (!_isInitialized && !_hasError)
                                    const Center(
                                      child:
                                          CircularProgressIndicator.adaptive(),
                                    ),
                                  if (_hasError)
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(20.0),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.error_outline,
                                              color: Colors.red,
                                              size: 48,
                                            ),
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
                                            if (_errorMessage != null) ...[
                                              const SizedBox(height: 8),
                                              Text(
                                                _errorMessage!,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (_isInitialized && !_isPlaying)
                                    Container(
                                      color: Colors.black26,
                                      child: const Center(
                                        child: Icon(
                                          Icons.play_arrow,
                                          size: 70,
                                          color: Colors.white,
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
                ),

                // ── Vaqt + boshqaruvlar ───────────────────────────────────
                if (_isInitialized && !_hasError) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: circleSize,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildTimeRow(),
                        const SizedBox(height: 4),
                        _buildControls(),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ✕ Yopish — o'ng yuqori
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

          // 🔇/🔊 Ovoz — chap yuqori
          if (_isInitialized && !_hasError)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: GestureDetector(
                onTap: _toggleMute,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: Icon(
                    _isMuted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Doiraviy progress arc chizuvchi CustomPainter ───────────────────────────

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final double radius;
  final bool showDot;

  const _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.radius,
    this.showDot = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Yuqoridan (-pi/2) soat yo'nalishida chizish
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );

    // Progress oxiridagi nuqta (draggable dot)
    if (showDot && progress > 0) {
      final dotAngle = startAngle + sweepAngle;
      final dotX = center.dx + radius * math.cos(dotAngle);
      final dotY = center.dy + radius * math.sin(dotAngle);

      // Tashqi aylana (oq)
      canvas.drawCircle(
        Offset(dotX, dotY),
        strokeWidth + 3,
        Paint()..color = Colors.white,
      );
      // Ichki aylana (ko'k)
      canvas.drawCircle(
        Offset(dotX, dotY),
        strokeWidth,
        Paint()..color = Colors.blue,
      );
    }
  }

  @override
  bool shouldRepaint(_CircularProgressPainter old) =>
      old.progress != progress || old.color != color;
}
