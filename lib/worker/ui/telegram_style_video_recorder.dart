import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:mone_task_app/worker/ui/video_pervi.dart';

class TelegramStyleVideoRecorder extends StatefulWidget {
  final int taskId;
  final int maxDuration;

  const TelegramStyleVideoRecorder({
    super.key,
    required this.taskId,
    required this.maxDuration,
  });

  @override
  State<TelegramStyleVideoRecorder> createState() =>
      _TelegramStyleVideoRecorderState();
}

class _TelegramStyleVideoRecorderState
    extends State<TelegramStyleVideoRecorder> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isInitialized = false;
  bool _isSwitchingCamera = false;
  int _currentCameraIndex = 1;
  int _recordedSeconds = 0;
  Timer? _timer;

  List<XFile> _videoSegments = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _showError("Kamera topilmadi");
        return;
      }

      _controller = CameraController(
        _cameras[_currentCameraIndex],
        ResolutionPreset.medium,
        fps: 20,
        enableAudio: true,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      _showError("Kamera xatoligi: $e");
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2) return;
    if (_isSwitchingCamera) return;

    setState(() {
      _isSwitchingCamera = true;
    });

    try {
      if (_isRecording && !_isPaused) {
        await _controller!.pauseVideoRecording();
        final currentVideo = await _controller!.stopVideoRecording();
        _videoSegments.add(currentVideo);
        print(
          'Segment ${_videoSegments.length} saqlandi: ${currentVideo.path}',
        );
      }

      _currentCameraIndex = _currentCameraIndex == 0 ? 1 : 0;

      await _controller?.dispose();

      _controller = CameraController(
        _cameras[_currentCameraIndex],
        ResolutionPreset.medium,
        fps: 20,
        enableAudio: true,
      );

      await _controller!.initialize();

      if (_isRecording && !_isPaused) {
        await _controller!.startVideoRecording();
        print('Yangi kamera bilan recording davom ettirildi');
      }

      if (mounted) {
        setState(() {
          _isSwitchingCamera = false;
        });
      }
    } catch (e) {
      setState(() {
        _isSwitchingCamera = false;
      });
      _showError("Kamerani almashtirishda xatolik: $e");
    }
  }

  void _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isRecording) return;

    try {
      await _controller!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _recordedSeconds = 0;
        _videoSegments.clear();
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && !_isPaused) {
          setState(() {
            _recordedSeconds++;
          });

          if (_recordedSeconds >= widget.maxDuration) {
            _stopRecording();
          }
        }
      });
    } catch (e) {
      _showError("Yozishni boshlab bo'lmadi: $e");
    }
  }

  void _togglePauseResume() async {
    if (!_isRecording) return;

    try {
      if (_isPaused) {
        // Resume
        await _controller!.resumeVideoRecording();
        setState(() {
          _isPaused = false;
        });
      } else {
        // Pause
        await _controller!.pauseVideoRecording();
        setState(() {
          _isPaused = true;
        });
      }
    } catch (e) {
      _showError("Pause/Resume xatoligi: $e");
    }
  }

  void _stopRecording() async {
    if (!_isRecording) return;

    _timer?.cancel();

    try {
      if (_isPaused) {
        await _controller!.resumeVideoRecording();
      }

      final XFile lastSegment = await _controller!.stopVideoRecording();
      _videoSegments.add(lastSegment);

      print('Jami ${_videoSegments.length} ta segment yozildi');

      setState(() {
        _isRecording = false;
        _isPaused = false;
      });

      if (_videoSegments.isNotEmpty) {
        // Preview ekraniga o'tish
        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VideoPreviewScreen(
              videoSegments: _videoSegments.map((e) => e.path).toList(),
              taskId: widget.taskId,
            ),
          ),
        );

        // Natijani qaytarish
        if (result != null && result is Map) {
          if (result['action'] == 'send') {
            Navigator.of(context).pop(_videoSegments);
          } else if (result['action'] == 'retake') {
            // Qaytadan yozish - ekranda qolish
            setState(() {
              _videoSegments.clear();
              _recordedSeconds = 0;
            });
          }
        }
      }
    } catch (e) {
      _showError("Videoni saqlashda xatolik: $e");
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // NULL CHECK MUAMMOSINI HAL QILISH
    if (!_isInitialized || _controller == null) {
      return const Material(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final size = MediaQuery.of(context).size;
    final deviceRatio = size.width / size.height;
    final scale = 1 / (_controller!.value.aspectRatio * deviceRatio);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // To'liq ekran kamera preview
          Positioned.fill(
            child: _isSwitchingCamera
                ? BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: Colors.black.withOpacity(0.5),
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  )
                : Transform.scale(
                    scale: scale,
                    child: Center(child: CameraPreview(_controller!)),
                  ),
          ),

          // Blur orqa fon faqat kamera tashqarisida
          Positioned.fill(
            child: CustomPaint(
              painter: CircleMaskPainter(
                circleRadius: size.width * 0.5,
                borderColor: _isRecording
                    ? (_isPaused ? Colors.orange : Colors.white)
                    : Colors.white,
                borderWidth: 4,
              ),
            ),
          ),

          // UI elementlar
          SafeArea(
            child: Column(
              children: [
                const Spacer(),

                // Timer va segment counter
                Column(
                  children: [
                    if (_isRecording)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _isPaused ? Colors.orange : Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isPaused
                                  ? Icons.pause_circle_filled
                                  : Icons.fiber_manual_record,
                              color: Colors.white,
                              size: 12,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "${_recordedSeconds ~/ 60}:${(_recordedSeconds % 60).toString().padLeft(2, '0')}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_isRecording && _videoSegments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Text(
                            'Qismlar: ${_videoSegments.length + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 40),

                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!_isRecording)
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),

                    // PAUSE/RESUME BUTTON
                    if (_isRecording) ...[
                      GestureDetector(
                        onTap: _togglePauseResume,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isPaused ? Icons.play_arrow : Icons.pause,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                    ] else
                      const SizedBox(width: 40),

                    // RECORD/STOP BUTTON
                    GestureDetector(
                      onTap: _isRecording ? _stopRecording : _startRecording,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: _isRecording ? 30 : 60,
                            height: _isRecording ? 30 : 60,
                            decoration: BoxDecoration(
                              color: _isRecording ? Colors.red : Colors.red,
                              borderRadius: BorderRadius.circular(
                                _isRecording ? 8 : 40,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    SizedBox(width: _isRecording ? 20 : 40),

                    // FLIP CAMERA BUTTON
                    if (_cameras.length > 1)
                      GestureDetector(
                        onTap: _isSwitchingCamera ? null : _toggleCamera,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: _isSwitchingCamera
                                ? Colors.black.withOpacity(0.3)
                                : Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: _isSwitchingCamera
                              ? const Padding(
                                  padding: EdgeInsets.all(18.0),
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.flip_camera_ios,
                                  color: Colors.white,
                                  size: 30,
                                ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Aylana mask yaratish uchun custom painter
class CircleMaskPainter extends CustomPainter {
  final double circleRadius;
  final Color borderColor;
  final double borderWidth;

  CircleMaskPainter({
    required this.circleRadius,
    required this.borderColor,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Blur orqa fon
    final blurPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: circleRadius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, blurPaint);

    // Aylana border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    canvas.drawCircle(center, circleRadius, borderPaint);
  }

  @override
  bool shouldRepaint(CircleMaskPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.circleRadius != circleRadius ||
        oldDelegate.borderWidth != borderWidth;
  }
}
