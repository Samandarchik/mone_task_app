import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class CircleVideoPlayer extends StatefulWidget {
  final List<String> videoUrls;
  final int initialIndex;
  final VoidCallback? onHalfWatched; // ← 50% ko'rilganda chaqiriladi

  const CircleVideoPlayer({
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
  bool _halfWatchedFired = false; // 50% faqat bir marta chaqirilsin
  late int _currentIndex;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
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
          });
          return;
        }
        if (await file.length() == 0) {
          setState(() {
            _hasError = true;
            _errorMessage = "Video fayl bo'sh";
          });
          return;
        }
        _controller = VideoPlayerController.file(file);
      } else {
        _controller = VideoPlayerController.networkUrl(Uri.parse(videoPath));
      }

      await _controller.initialize();
      await _controller.setLooping(false);
      await _controller.play();

      _controller.addListener(_onVideoListener);

      setState(() {
        _isInitialized = true;
        _isPlaying = true;
      });

      _animationController.reset();
      _animationController.forward();
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
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

    // 50% tekshirish — faqat bir marta
    if (!_halfWatchedFired && total > 0 && current >= total * 0.5) {
      _halfWatchedFired = true;
      widget.onHalfWatched?.call();
    }

    // Video tugasa keyingiga o'tish
    if (!value.isPlaying && current >= total - 200) {
      _goToNext();
    }
  }

  void _goToNext() {
    if (_hasNext) {
      setState(() => _currentIndex++);
      _initializeVideo();
    }
  }

  void _goToPrev() {
    if (_hasPrev) {
      setState(() => _currentIndex--);
      _initializeVideo();
    }
  }

  @override
  void dispose() {
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

  Widget _buildProgressBar(double circleSize) {
    final duration = _controller.value.duration;
    final position = _controller.value.position;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : position.inMilliseconds / duration.inMilliseconds;
    final progressWidth = circleSize * 0.9;

    return Container(
      width: progressWidth,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.videoUrls.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${_currentIndex + 1} / ${widget.videoUrls.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              Text(
                _formatDuration(duration),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onHorizontalDragUpdate: (d) =>
                _seekTo(d.localPosition.dx, progressWidth - 32),
            onTapDown: (d) => _seekTo(d.localPosition.dx, progressWidth - 32),
            child: Container(
              height: 30,
              color: Colors.transparent,
              child: Stack(
                children: [
                  Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (progressWidth - 32) * progress.clamp(0.0, 1.0),
                    top: 7,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
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
              const SizedBox(width: 8),
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
                  size: 40,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _hasNext ? _goToNext : null,
                icon: Icon(
                  Icons.skip_next_rounded,
                  color: _hasNext ? Colors.white : Colors.white30,
                  size: 32,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _seekTo(double x, double width) {
    final d = _controller.value.duration;
    final ratio = (x - 16).clamp(0.0, width) / width;
    _controller.seekTo(d * ratio);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final circleSize = size.width * 0.85;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
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
                                child: CircularProgressIndicator.adaptive(),
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
                if (_isInitialized && !_hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: _buildProgressBar(circleSize),
                  ),
              ],
            ),
          ),
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
          if (_isInitialized && !_hasError)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _controller.setVolume(_controller.value.volume > 0 ? 0 : 1);
                  });
                },
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: Icon(
                    _controller.value.volume > 0
                        ? Icons.volume_up
                        : Icons.volume_off,
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
