import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:video_player/video_player.dart';

class CircleVideoPlayer2 extends StatefulWidget {
  final String videoUrl;

  /// Video 50% ko'rilganda bir marta chaqiriladi
  final VoidCallback? onHalfWatched;

  const CircleVideoPlayer2({
    super.key,
    required this.videoUrl,
    this.onHalfWatched,
  });

  @override
  State<CircleVideoPlayer2> createState() => _CircleVideoPlayer2State();
}

class _CircleVideoPlayer2State extends State<CircleVideoPlayer2>
    with SingleTickerProviderStateMixin {
  static bool get _useMediaKit => Platform.isWindows;

  // ── video_player (iOS/Android/macOS) ──
  VideoPlayerController? _controller;

  // ── media_kit (Windows) ──
  mk.Player? _mkPlayer;
  mkv.VideoController? _mkController;
  StreamSubscription? _mkPlayingSub;
  StreamSubscription? _mkPositionSub;
  StreamSubscription? _mkDurationSub;
  StreamSubscription? _mkErrorSub;

  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  String? _errorMessage;

  // 50% callback bir marta chaqirilsin
  bool _halfWatchedFired = false;
  // Video real ijro vaqtini hisoblash uchun
  Duration _watchedDuration = Duration.zero;
  DateTime? _lastTickTime;

  // media_kit state
  Duration _mkPosition = Duration.zero;
  Duration _mkDuration = Duration.zero;

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

      if (videoPath.contains('://') && videoPath.contains('/Users/')) {
        final m = RegExp(r'/Users/.*').firstMatch(videoPath);
        if (m != null) videoPath = m.group(0)!;
      } else if (videoPath.contains('://') && videoPath.contains('/data/')) {
        final m = RegExp(r'/data/.*').firstMatch(videoPath);
        if (m != null) videoPath = m.group(0)!;
      }

      final isLocal =
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
            _errorMessage = 'Video fayl bo\'sh';
          });
          return;
        }
      }

      if (_useMediaKit) {
        await _initMkPlayer(videoPath, isLocal);
      } else {
        await _initVideoPlayerController(videoPath, isLocal);
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _initVideoPlayerController(String videoPath, bool isLocal) async {
    if (isLocal) {
      _controller = VideoPlayerController.file(File(videoPath));
    } else {
      _controller = VideoPlayerController.networkUrl(Uri.parse(videoPath));
    }

    await _controller!.initialize();
    await _controller!.setLooping(true);
    await _controller!.play();

    _controller!.addListener(_onVideoProgress);

    setState(() {
      _isInitialized = true;
      _isPlaying = true;
    });
  }

  Future<void> _initMkPlayer(String videoPath, bool isLocal) async {
    _mkPlayer = mk.Player();
    _mkController = mkv.VideoController(_mkPlayer!);

    _mkPlayingSub = _mkPlayer!.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
        _updateHalfWatchMk();
      }
    });

    _mkPositionSub = _mkPlayer!.stream.position.listen((pos) {
      if (mounted) {
        setState(() => _mkPosition = pos);
        _updateHalfWatchMk();
      }
    });

    _mkDurationSub = _mkPlayer!.stream.duration.listen((dur) {
      if (mounted) setState(() => _mkDuration = dur);
    });

    _mkErrorSub = _mkPlayer!.stream.error.listen((error) {
      if (error.isNotEmpty && mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = error;
        });
      }
    });

    final mediaUri = isLocal ? 'file://$videoPath' : videoPath;
    await _mkPlayer!.open(mk.Media(mediaUri));
    await _mkPlayer!.setPlaylistMode(mk.PlaylistMode.loop);

    setState(() {
      _isInitialized = true;
      _isPlaying = true;
    });
  }

  void _updateHalfWatchMk() {
    if (_halfWatchedFired) return;
    if (_mkDuration.inMilliseconds == 0) return;

    if (_isPlaying) {
      final now = DateTime.now();
      if (_lastTickTime != null) {
        final delta = now.difference(_lastTickTime!);
        if (delta.inMilliseconds < 500) {
          _watchedDuration += delta;
        }
      }
      _lastTickTime = now;
    } else {
      _lastTickTime = null;
    }

    final halfDuration = _mkDuration ~/ 2;
    if (_watchedDuration >= halfDuration) {
      _halfWatchedFired = true;
      widget.onHalfWatched?.call();
    }
  }

  void _onVideoProgress() {
    if (mounted) setState(() {});

    if (_halfWatchedFired) return;
    if (!_controller!.value.isInitialized) return;

    final duration = _controller!.value.duration;
    if (duration.inMilliseconds == 0) return;

    if (_controller!.value.isPlaying) {
      final now = DateTime.now();
      if (_lastTickTime != null) {
        final delta = now.difference(_lastTickTime!);
        if (delta.inMilliseconds < 500) {
          _watchedDuration += delta;
        }
      }
      _lastTickTime = now;
    } else {
      _lastTickTime = null;
    }

    final halfDuration = duration ~/ 2;
    if (_watchedDuration >= halfDuration) {
      _halfWatchedFired = true;
      widget.onHalfWatched?.call();
    }
  }

  @override
  void dispose() {
    if (_useMediaKit) {
      _mkPlayingSub?.cancel();
      _mkPositionSub?.cancel();
      _mkDurationSub?.cancel();
      _mkErrorSub?.cancel();
      _mkPlayer?.dispose();
    } else {
      _controller?.removeListener(_onVideoProgress);
      _controller?.dispose();
    }
    _animationController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  Duration get _currentPosition {
    if (_useMediaKit) return _mkPosition;
    return _controller?.value.position ?? Duration.zero;
  }

  Duration get _currentDuration {
    if (_useMediaKit) return _mkDuration;
    return _controller?.value.duration ?? Duration.zero;
  }

  Widget _buildVideoWidget() {
    if (_useMediaKit && _mkController != null) {
      return mkv.Video(
        controller: _mkController!,
        fill: Colors.black,
      );
    }
    if (_controller != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildProgressBar(double circleSize) {
    final duration = _currentDuration;
    final position = _currentPosition;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : position.inMilliseconds / duration.inMilliseconds;
    final progressWidth = circleSize * 0.9;

    return Container(
      width: progressWidth,
      margin: const EdgeInsets.symmetric(vertical: 60),
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
        ],
      ),
    );
  }

  void _seekTo(double x, double width) {
    final d = _currentDuration;
    final ratio = (x - 16).clamp(0.0, width) / width;
    if (_useMediaKit) {
      _mkPlayer?.seek(d * ratio);
    } else {
      _controller?.seekTo(d * ratio);
    }
  }

  void _toggleVolume() {
    if (_useMediaKit) {
      final currentVol = _mkPlayer?.state.volume ?? 100.0;
      _mkPlayer?.setVolume(currentVol > 0 ? 0.0 : 100.0);
    } else {
      _controller?.setVolume((_controller!.value.volume > 0) ? 0 : 1);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final circleSize = size.width * 0.85;

    final bool volumeOn = _useMediaKit
        ? (_mkPlayer?.state.volume ?? 100.0) > 0
        : (_controller?.value.volume ?? 1.0) > 0;

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

          Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.1),
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
                      boxShadow: const [
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
                            _buildVideoWidget(),

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
                onTap: _toggleVolume,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: Icon(
                    volumeOn ? Icons.volume_up : Icons.volume_off,
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
