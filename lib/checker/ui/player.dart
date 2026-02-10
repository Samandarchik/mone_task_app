import 'dart:io';
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
  String? _errorMessage;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      String videoPath = widget.videoUrl;

      // MUAMMO: Agar URL http bilan boshlansa, lekin ichida local path bo'lsa
      // Masalan: https://example.com//Users/...
      // Buni to'g'rilash kerak
      if (videoPath.contains('://') && videoPath.contains('/Users/')) {
        // Local path ni ajratib olish
        final localPathMatch = RegExp(r'/Users/.*').firstMatch(videoPath);
        if (localPathMatch != null) {
          videoPath = localPathMatch.group(0)!;
        }
      } else if (videoPath.contains('://') && videoPath.contains('/data/')) {
        // Android uchun ham
        final localPathMatch = RegExp(r'/data/.*').firstMatch(videoPath);
        if (localPathMatch != null) {
          videoPath = localPathMatch.group(0)!;
        }
      }

      // Avtomatik ravishda local yoki network ekanligini aniqlash
      bool isLocal =
          !videoPath.startsWith('http://') && !videoPath.startsWith('https://');

      if (isLocal) {
        // LOCAL FILE
        final file = File(videoPath);

        if (await file.exists()) {}

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
            _errorMessage = 'Video fayl bo\'sh';
          });
          return;
        }

        _controller = VideoPlayerController.file(file);
      } else {
        // NETWORK URL
        _controller = VideoPlayerController.networkUrl(Uri.parse(videoPath));
      }

      await _controller.initialize();
      await _controller.setLooping(true);
      await _controller.play();

      _controller.addListener(() {
        if (mounted) setState(() {});
      });

      setState(() {
        _isInitialized = true;
        _isPlaying = true;
      });
    } catch (e) {
      print('Video yuklashda xatolik: $e');
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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

          /// Slider
          GestureDetector(
            onHorizontalDragUpdate: (details) =>
                _seekTo(details.localPosition.dx, progressWidth - 32),
            onTapDown: (details) =>
                _seekTo(details.localPosition.dx, progressWidth - 32),
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
          /// Back tap -> close
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
                /// Circle Video
                ScaleTransition(
                  scale: Tween(begin: 0.8, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _animationController,
                      curve: Curves.easeOut,
                    ),
                  ),
                  child: Container(
                    width: circleSize,
                    height: circleSize,
                    decoration: BoxDecoration(
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

                if (_isInitialized && !_hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: _buildProgressBar(circleSize),
                  ),
              ],
            ),
          ),

          /// Close button
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

          /// Volume
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
