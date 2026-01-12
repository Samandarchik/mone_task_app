// Aylana Video Player (Telegram kabi)
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class CircleVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const CircleVideoPlayer({super.key, required this.videoUrl});

  @override
  State<CircleVideoPlayer> createState() => _CircleVideoPlayerState();
}

class _CircleVideoPlayerState extends State<CircleVideoPlayer>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.forward();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _controller.initialize();
      await _controller.setLooping(true);
      await _controller.play();

      // Video pozitsiyasini kuzatish
      _controller.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });

      setState(() {
        _isInitialized = true;
        _isPlaying = true;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
      });
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _isPlaying = false;
      } else {
        _controller.play();
        _isPlaying = true;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // Vaqtni format qilish (mm:ss)
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  // Progress Bar with draggable seek
  Widget _buildProgressBar(double circleSize) {
    final duration = _controller.value.duration;
    final position = _controller.value.position;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    final progressWidth =
        circleSize * 0.9; // Progress bar aylana kengligidan biroz kichik

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
          // Time labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Progress slider
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              _seekToPosition(details.localPosition.dx, progressWidth - 32);
            },
            onTapDown: (details) {
              _seekToPosition(details.localPosition.dx, progressWidth - 32);
            },
            child: Container(
              height: 30,
              color: Colors.transparent,
              alignment: Alignment.center,
              child: Stack(
                children: [
                  // Background bar
                  Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  // Progress bar
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue, Colors.blueAccent],
                        ),
                        borderRadius: BorderRadius.circular(2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Draggable indicator
                  Positioned(
                    left: (progressWidth - 32) * progress.clamp(0.0, 1.0) - 8,
                    top: 7, // Vertikal markazga joylashtirish (30 / 2 - 16 / 2)
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Seek to position helper
  void _seekToPosition(double localX, double totalWidth) {
    final duration = _controller.value.duration;
    final ratio = (localX - 16).clamp(0.0, totalWidth) / totalWidth;
    final newPosition = duration * ratio;
    _controller.seekTo(newPosition);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final circleSize = size.width * 0.85;

    return GestureDetector(
      onTap: () {
        if (_isInitialized) {
          _togglePlayPause();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Tap anywhere to close
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(color: Colors.transparent),
              ),
            ),

            // Circle Video Container
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                      CurvedAnimation(
                        parent: _animationController,
                        curve: Curves.easeOut,
                      ),
                    ),
                    child: GestureDetector(
                      onTap: () {
                        if (_isInitialized) {
                          _togglePlayPause();
                        }
                      },
                      child: Container(
                        width: circleSize,
                        height: circleSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Video Player
                              if (_isInitialized && !_hasError)
                                FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _controller.value.size.width,
                                    height: _controller.value.size.height,
                                    child: VideoPlayer(_controller),
                                  ),
                                ),

                              // Loading
                              if (!_isInitialized && !_hasError)
                                const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                ),

                              // Error
                              if (_hasError)
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: Colors.red,
                                        size: 48,
                                      ),
                                      const SizedBox(height: 16),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 32,
                                        ),
                                        child: Text(
                                          'Video yuklanmadi',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              // Play/Pause Overlay
                              if (_isInitialized && !_isPlaying)
                                Container(
                                  color: Colors.black26,
                                  child: const Center(
                                    child: Icon(
                                      Icons.play_arrow_rounded,
                                      size: 80,
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

                  // Progress Bar - aylana tashqarida pastda
                  if (_isInitialized && !_hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: _buildProgressBar(circleSize),
                    ),
                ],
              ),
            ),

            // Close button
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 28),
                ),
              ),
            ),

            // Mute/Unmute button
            if (_isInitialized && !_hasError)
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_controller.value.volume > 0) {
                        _controller.setVolume(0);
                      } else {
                        _controller.setVolume(1);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _controller.value.volume > 0
                          ? Icons.volume_up
                          : Icons.volume_off,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
