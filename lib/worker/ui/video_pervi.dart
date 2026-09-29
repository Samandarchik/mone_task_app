import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:video_player/video_player.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';

class VideoPreviewScreen extends StatefulWidget {
  final List<String> videoSegments;
  final int taskId;

  const VideoPreviewScreen({
    super.key,
    required this.videoSegments,
    required this.taskId,
  });

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  static bool get _useMediaKit => Platform.isWindows;

  // video_player (iOS/Android/macOS)
  VideoPlayerController? _controller;

  // media_kit (Windows)
  mk.Player? _mkPlayer;
  mkv.VideoController? _mkController;

  bool _isInitialized = false;
  bool _isPlaying = false;
  int _currentSegmentIndex = 0;
  bool _isLoadingNextSegment = false;

  /// Tugma ikki marta bosilmasin (ikki marta yuborish bo'lmasin).
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _initializeCurrentSegment();
  }

  Future<void> _initializeCurrentSegment() async {
    if (_currentSegmentIndex >= widget.videoSegments.length) {
      _currentSegmentIndex = 0;
    }

    try {
      if (_useMediaKit) {
        await _mkPlayer?.dispose();
        _mkPlayer = mk.Player();
        _mkController = mkv.VideoController(_mkPlayer!);

        _mkPlayer!.stream.completed.listen((completed) {
          if (completed && !_isLoadingNextSegment) {
            _playNextSegment();
          }
        });

        _mkPlayer!.stream.playing.listen((playing) {
          if (mounted) setState(() => _isPlaying = playing);
        });

        final path = widget.videoSegments[_currentSegmentIndex];
        await _mkPlayer!.open(mk.Media('file://$path'));

        if (mounted) {
          setState(() {
            _isInitialized = true;
            _isLoadingNextSegment = false;
            _isPlaying = true;
          });
        }
      } else {
        await _controller?.dispose();

        _controller = VideoPlayerController.file(
          File(widget.videoSegments[_currentSegmentIndex]),
        );

        await _controller!.initialize();

        if (mounted) {
          setState(() {
            _isInitialized = true;
            _isLoadingNextSegment = false;
          });

          _controller!.play();
          setState(() {
            _isPlaying = true;
          });

          _controller!.addListener(_onVideoProgress);
        }
      }
    } catch (e) {
      debugPrint('Video preview xatolik: $e');
      _showError(tr("Videoni ochib bo'lmadi. Baribir yuborishingiz mumkin."));
    }
  }

  void _onVideoProgress() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_controller!.value.position >= _controller!.value.duration) {
      if (!_isLoadingNextSegment) {
        _playNextSegment();
      }
    }
  }

  Future<void> _playNextSegment() async {
    if (!mounted) return;
    setState(() {
      _isLoadingNextSegment = true;
    });

    _currentSegmentIndex++;

    if (_currentSegmentIndex >= widget.videoSegments.length) {
      // Barchasi tugadi, qayta boshidan
      _currentSegmentIndex = 0;
    }

    await _initializeCurrentSegment();
  }

  void _togglePlayPause() {
    if (_useMediaKit) {
      _mkPlayer?.playOrPause();
      return;
    }
    if (_controller == null) return;

    setState(() {
      if (_isPlaying) {
        _controller!.pause();
        _isPlaying = false;
      } else {
        _controller!.play();
        _isPlaying = true;
      }
    });
  }

  void _sendVideo() {
    if (_closing) return;
    setState(() => _closing = true);
    Navigator.of(
      context,
    ).pop({'action': 'send', 'segments': widget.videoSegments});
  }

  void _retakeVideo() {
    if (_closing) return;
    setState(() => _closing = true);
    Navigator.of(context).pop({'action': 'retake'});
  }

  void _showError(String message) {
    if (!mounted) return;
    showAppSnack(context, message, type: SnackType.error);
  }

  @override
  void dispose() {
    if (_useMediaKit) {
      _mkPlayer?.dispose();
    } else {
      _controller?.removeListener(_onVideoProgress);
      _controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final circleRadius = size.width * 0.5;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video player (to'liq ekran)
          if (_isInitialized)
            Positioned.fill(
              child: _useMediaKit && _mkController != null
                  ? mkv.Video(
                      controller: _mkController!,
                      fill: Colors.black,
                    )
                  : (_controller != null
                      ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _controller!.value.size.width,
                            height: _controller!.value.size.height,
                            child: VideoPlayer(_controller!),
                          ),
                        )
                      : SizedBox.shrink()),
            ),

          // Yuklash indikatori
          if (!_isInitialized || _isLoadingNextSegment)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),

          // Aylana mask - faqat markazni ko'rsatish
          if (_isInitialized)
            Positioned.fill(
              child: CustomPaint(
                painter: CirclePreviewMaskPainter(
                  circleRadius: circleRadius,
                  borderColor: Colors.white,
                  borderWidth: 4,
                ),
              ),
            ),

          // Play/Pause overlay (markazda)
          if (_isInitialized && !_isLoadingNextSegment)
            Center(
              child: GestureDetector(
                onTap: _togglePlayPause,
                behavior: HitTestBehavior.translucent,
                child: Container(
                  width: circleRadius * 2,
                  height: circleRadius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.transparent,
                  ),
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _isPlaying ? 0.0 : 0.8,
                      duration: Duration(milliseconds: 300),
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 50,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      tr("Videoni ko'ring va yuboring"),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                      ),
                    ),
                  ),
                  // Segment counter va progress
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Segment progress dots
                      if (widget.videoSegments.length > 1)
                        Padding(
                          padding: EdgeInsets.only(top: 8, left: 8),
                          child: Row(
                            children: List.generate(
                              widget.videoSegments.length,
                              (index) => Container(
                                margin: EdgeInsets.only(right: 4),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: index <= _currentSegmentIndex
                                      ? Colors.white
                                      : Colors.white38,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom buttons
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 480),
                    child: Row(
                      children: [
                        // Qaytadan olish
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _closing ? null : _retakeVideo,
                            icon: Icon(Icons.refresh_rounded),
                            label: Text(tr('Qaytadan')),
                          ),
                        ),
                        SizedBox(width: 12),
                        // Yuborish
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _closing ? null : _sendVideo,
                            icon: Icon(Icons.send_rounded),
                            label: Text(tr('Yuborish')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Aylana mask painter - faqat markazni ko'rsatish
class CirclePreviewMaskPainter extends CustomPainter {
  final double circleRadius;
  final Color borderColor;
  final double borderWidth;

  CirclePreviewMaskPainter({
    required this.circleRadius,
    required this.borderColor,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Oq orqa fon (aylana tashqarisi)
    final whitePaint = Paint()..color = Colors.white;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: circleRadius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, whitePaint);

    // Aylana border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    canvas.drawCircle(center, circleRadius, borderPaint);
  }

  @override
  bool shouldRepaint(CirclePreviewMaskPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.circleRadius != circleRadius ||
        oldDelegate.borderWidth != borderWidth;
  }
}
