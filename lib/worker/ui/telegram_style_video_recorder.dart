import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:mone_task_app/worker/ui/video_pervi.dart';

class TelegramStyleVideoRecorder extends StatefulWidget {
  final int taskId;

  const TelegramStyleVideoRecorder({super.key, required this.taskId});

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

  // ── ZOOM ──────────────────────────────────────────────
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 16.0; // 16x gacha
  bool _showZoomSlider = false;
  Timer? _zoomSliderHideTimer;
  // ──────────────────────────────────────────────────────

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
        ResolutionPreset.high,
        fps: 30,
        enableAudio: true,
      );

      await _controller!.initialize();

      // Zoom chegaralarini olish (max 16x gacha cheklash)
      _minZoom = await _controller!.getMinZoomLevel();
      final double deviceMax = await _controller!.getMaxZoomLevel();
      _maxZoom = deviceMax.clamp(_minZoom, 16.0);
      _currentZoom = _minZoom;

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
      }

      _currentCameraIndex = _currentCameraIndex == 0 ? 1 : 0;

      await _controller?.dispose();

      _controller = CameraController(
        _cameras[_currentCameraIndex],
        ResolutionPreset.high,
        fps: 30,
        enableAudio: true,
      );

      await _controller!.initialize();

      // Yangi kamera uchun zoom chegaralarini yangilash (max 16x)
      _minZoom = await _controller!.getMinZoomLevel();
      final double newDeviceMax = await _controller!.getMaxZoomLevel();
      _maxZoom = newDeviceMax.clamp(_minZoom, 16.0);
      _currentZoom = _minZoom;
      await _controller!.setZoomLevel(_currentZoom);

      if (_isRecording && !_isPaused) {
        await _controller!.startVideoRecording();
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

  // ── ZOOM SLIDER ───────────────────────────────────────
  void _onZoomChanged(double value) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final clamped = value.clamp(_minZoom, _maxZoom);
    _currentZoom = clamped;
    _controller!.setZoomLevel(_currentZoom);

    // 3 soniyadan keyin sliderni yashirish
    _zoomSliderHideTimer?.cancel();
    _zoomSliderHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showZoomSlider = false);
    });

    setState(() => _showZoomSlider = true);
  }
  // ──────────────────────────────────────────────────────

  void _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isRecording) return;

    try {
      await _controller!.startVideoRecording();
      await WakelockPlus.enable(); // Ekran uchmasin
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

          if (_recordedSeconds >= 40) {
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
        await _controller!.resumeVideoRecording();
        setState(() {
          _isPaused = false;
        });
      } else {
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

      await WakelockPlus.disable(); // Ekran normal rejimga qaytsin

      setState(() {
        _isRecording = false;
        _isPaused = false;
      });

      if (_videoSegments.isNotEmpty) {
        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VideoPreviewScreen(
              videoSegments: _videoSegments.map((e) => e.path).toList(),
              taskId: widget.taskId,
            ),
          ),
        );

        if (result != null && result is Map) {
          if (result['action'] == 'send') {
            Navigator.of(context).pop(_videoSegments);
          } else if (result['action'] == 'retake') {
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
    _zoomSliderHideTimer?.cancel();
    WakelockPlus.disable(); // Widget yopilganda ham o'chirish
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          // ── Kamera preview + ZOOM GESTURE ───────────────
          Positioned.fill(
            child: _isSwitchingCamera
                ? BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                  )
                : Transform.scale(
                    scale: scale,
                    child: Center(child: CameraPreview(_controller!)),
                  ),
          ),

          // Blur mask (doira tashqarisi)
          Positioned.fill(
            child: CustomPaint(
              painter: CircleMaskPainter(
                circleRadius: size.width * 0.5,
                borderColor: _isRecording
                    ? (_isPaused ? Colors.orange : Colors.red)
                    : Colors.white,
                borderWidth: 6,
                progress: _isRecording
                    ? (_recordedSeconds / 40).clamp(0.0, 1.0)
                    : 0.0,
              ),
            ),
          ),

          // ─────────────────────────────────────────────────

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

                const SizedBox(height: 16),

                // ── Gorizontal ZOOM SLIDER (chapdan o'ngga) ──
                AnimatedOpacity(
                  opacity: _showZoomSlider ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 300),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        // Min label
                        Text(
                          '1×',
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Slider
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 10,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 20,
                              ),
                              activeTrackColor: Colors.black,
                              inactiveTrackColor: Colors.black.withOpacity(0.3),
                              thumbColor: Colors.black,
                              overlayColor: Colors.black.withOpacity(0.2),
                            ),
                            child: Slider(
                              value: _currentZoom.clamp(_minZoom, _maxZoom),
                              min: _minZoom,
                              max: _maxZoom,
                              onChanged: _onZoomChanged,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Zoom qiymati + max label
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_currentZoom.toStringAsFixed(1)}×',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ─────────────────────────────────────────────
                const SizedBox(height: 16),

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
                              color: Colors.red,
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

class CircleMaskPainter extends CustomPainter {
  final double circleRadius;
  final Color borderColor;
  final double borderWidth;
  final double progress;

  CircleMaskPainter({
    required this.circleRadius,
    required this.borderColor,
    required this.borderWidth,
    this.progress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scaledRadius = circleRadius * 0.9;

    final blurPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: scaledRadius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, blurPaint);

    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    canvas.drawCircle(center, scaledRadius, bgPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeCap = StrokeCap.round;

      final rect = Rect.fromCircle(center: center, radius: scaledRadius);

      canvas.drawArc(
        rect,
        -3.14159 / 2,
        2 * 3.14159 * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(CircleMaskPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.circleRadius != circleRadius ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.progress != progress;
  }
}
