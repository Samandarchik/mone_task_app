import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _isFrontCamera = false;
  int _recordedSeconds = 0;
  Timer? _timer;

  List<XFile> _videoSegments = [];

  static const _nativeCameraChannel = MethodChannel('native_camera');
  List<Map<String, dynamic>> _iosLenses = [];
  int _currentBackLensIndex = -1;
  List<Map<String, dynamic>> _zoomSteps = [];

  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 16.0;
  final Map<int, Offset> _pointers = {};
  double? _initialPinchDistance;

  bool _showZoomLabel = false;
  Timer? _zoomLabelTimer;

  bool _isDraggingLensButton = false;
  double _dragStartX = 0;
  double _dragStartZoom = 1.0;

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
      if (Platform.isIOS) {
        await _setupIOSLenses();
      } else {
        _setupAndroidZoomSteps();
      }
      await _openCamera(_getInitialCameraIndex());
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      _showError("Kamera xatoligi: $e");
    }
  }

  Future<void> _setupIOSLenses() async {
    try {
      final result = await _nativeCameraChannel.invokeMethod(
        'getAvailableLenses',
      );
      if (result is List) {
        _iosLenses = result
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (e) {
      debugPrint("iOS lens xatolik: $e");
    }

    _zoomSteps = [];
    final backLenses = _iosLenses
        .where((l) => l['position'] == 'back')
        .toList();
    for (int i = 0; i < backLenses.length; i++) {
      final lens = backLenses[i];
      final lensType = lens['lensType'] as String? ?? 'wide';
      if (lensType == 'ultraWide' || lensType == 'wide') {
        _zoomSteps.add({
          'label': lens['zoomLabel'] as String? ?? '1×',
          'value': (lens['zoomValue'] as num?)?.toDouble() ?? 1.0,
          'lensType': lensType,
          'backLensIndex': i,
        });
      }
    }
    if (_zoomSteps.isEmpty) {
      _zoomSteps = [
        {'label': '1×', 'value': 1.0, 'lensType': 'wide', 'backLensIndex': 0},
      ];
    }
    _currentBackLensIndex = _zoomSteps.indexWhere(
      (s) => s['lensType'] == 'wide',
    );
    if (_currentBackLensIndex < 0) _currentBackLensIndex = 0;
  }

  void _setupAndroidZoomSteps() {
    _zoomSteps = [
      {'label': '1×', 'value': 1.0, 'lensType': 'wide', 'backLensIndex': 0},
    ];
    _currentBackLensIndex = 0;
  }

  int _getInitialCameraIndex() => 0;

  int _findCameraIndexForLens(String lensType) {
    if (!Platform.isIOS) return 0;
    final backLenses = _iosLenses
        .where((l) => l['position'] == 'back')
        .toList();
    final lensInfo = backLenses.firstWhere(
      (l) => l['lensType'] == lensType,
      orElse: () => backLenses.isNotEmpty ? backLenses[0] : {},
    );
    if (lensInfo.isEmpty) return 0;
    final uniqueID = lensInfo['uniqueID'] as String?;
    if (uniqueID == null) return 0;
    for (int i = 0; i < _cameras.length; i++) {
      if (_cameras[i].name == uniqueID) return i;
    }
    for (int i = 0; i < _cameras.length; i++) {
      if (_cameras[i].lensDirection == CameraLensDirection.back) return i;
    }
    return 0;
  }

  int _findFrontCameraIndex() {
    for (int i = 0; i < _cameras.length; i++) {
      if (_cameras[i].lensDirection == CameraLensDirection.front) return i;
    }
    return 0;
  }

  Future<void> _openCamera(int cameraIndex) async {
    await _controller?.dispose();
    _controller = CameraController(
      _cameras[cameraIndex],
      ResolutionPreset.high,
      fps: 30,
      enableAudio: true,
    );
    await _controller!.initialize();
    _minZoom = await _controller!.getMinZoomLevel();
    final deviceMax = await _controller!.getMaxZoomLevel();
    _maxZoom = deviceMax.clamp(_minZoom, 16.0);
    _currentZoom = (1.0).clamp(_minZoom, _maxZoom);
    await _controller!.setZoomLevel(_currentZoom);
  }

  Future<void> _toggleLens() async {
    if (_isSwitchingCamera || _isFrontCamera) return;
    if (_zoomSteps.length <= 1) return;
    int nextIndex = -1;
    for (int i = 0; i < _zoomSteps.length; i++) {
      if (_isStepActive(_zoomSteps[i])) {
        nextIndex = (i + 1) % _zoomSteps.length;
        break;
      }
    }
    if (nextIndex < 0) nextIndex = 0;
    final step = _zoomSteps[nextIndex];
    final lensType = step['lensType'] as String;
    final backLensIndex = step['backLensIndex'] as int;
    if (Platform.isIOS && backLensIndex != _currentBackLensIndex) {
      await _switchToLens(lensType, backLensIndex);
    }
    HapticFeedback.lightImpact();
  }

  Future<void> _switchToLens(String lensType, int backLensIndex) async {
    setState(() => _isSwitchingCamera = true);
    try {
      if (_isRecording && !_isPaused) {
        await _controller!.pauseVideoRecording();
        final seg = await _controller!.stopVideoRecording();
        _videoSegments.add(seg);
      }
      final cameraIdx = _findCameraIndexForLens(lensType);
      await _openCamera(cameraIdx);
      _currentBackLensIndex = backLensIndex;
      if (_isRecording && !_isPaused) {
        await _controller!.startVideoRecording();
      }
      if (mounted) setState(() => _isSwitchingCamera = false);
    } catch (e) {
      if (mounted) setState(() => _isSwitchingCamera = false);
      _showError("Lensni almashtirishda xatolik: $e");
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2 || _isSwitchingCamera) return;
    setState(() => _isSwitchingCamera = true);
    try {
      if (_isRecording && !_isPaused) {
        await _controller!.pauseVideoRecording();
        final seg = await _controller!.stopVideoRecording();
        _videoSegments.add(seg);
      }
      int targetIdx;
      if (_isFrontCamera) {
        if (Platform.isIOS && _currentBackLensIndex >= 0) {
          final step = _zoomSteps[_currentBackLensIndex];
          targetIdx = _findCameraIndexForLens(step['lensType'] as String);
        } else {
          targetIdx = 0;
        }
        _isFrontCamera = false;
      } else {
        targetIdx = _findFrontCameraIndex();
        _isFrontCamera = true;
      }
      await _openCamera(targetIdx);
      if (_isRecording && !_isPaused) {
        await _controller!.startVideoRecording();
      }
      if (mounted) setState(() => _isSwitchingCamera = false);
    } catch (e) {
      if (mounted) setState(() => _isSwitchingCamera = false);
      _showError("Kamerani almashtirishda xatolik: $e");
    }
  }

  void _setZoom(double zoom) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    _currentZoom = clamped;
    _controller!.setZoomLevel(_currentZoom);
    setState(() {});
  }

  void _showZoomLabelTemporarily() {
    _zoomLabelTimer?.cancel();
    _showZoomLabel = true;
    _zoomLabelTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showZoomLabel = false);
    });
    setState(() {});
  }

  void _handlePointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
  }

  void _handlePointerMove(PointerMoveEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length < 2) return;
    if (_controller == null || !_controller!.value.isInitialized) return;
    final offsets = _pointers.values.toList();
    final currentDist = (offsets[0] - offsets[1]).distance;
    if (_initialPinchDistance == null) {
      _initialPinchDistance = currentDist;
      _baseZoom = _currentZoom;
      return;
    }
    final scale = currentDist / _initialPinchDistance!;
    final newZoom = (_baseZoom * scale).clamp(_minZoom, _maxZoom);
    if ((newZoom - _currentZoom).abs() < 0.01) return;
    _currentZoom = newZoom;
    _controller!.setZoomLevel(_currentZoom);
    _showZoomLabelTemporarily();
  }

  void _handlePointerUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _initialPinchDistance = null;
  }

  void _onLensLongPressStart(LongPressStartDetails details) {
    _isDraggingLensButton = true;
    _dragStartX = details.globalPosition.dx;
    _dragStartZoom = _currentZoom;
    HapticFeedback.mediumImpact();
    _zoomLabelTimer?.cancel();
    setState(() => _showZoomLabel = true);
  }

  void _onLensLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isDraggingLensButton) return;
    final dx = details.globalPosition.dx - _dragStartX;
    final double zoomRange = _maxZoom - _minZoom;
    final double zoomDelta = (dx / 250) * zoomRange;
    final double newZoom = (_dragStartZoom + zoomDelta).clamp(
      _minZoom,
      _maxZoom,
    );
    _setZoom(newZoom);
    _zoomLabelTimer?.cancel();
    setState(() => _showZoomLabel = true);
  }

  void _onLensLongPressEnd(LongPressEndDetails details) {
    _isDraggingLensButton = false;
    _zoomLabelTimer?.cancel();
    _zoomLabelTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showZoomLabel = false);
    });
    setState(() {});
  }

  void _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isRecording) return;
    try {
      await _controller!.startVideoRecording();
      await WakelockPlus.enable();
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _recordedSeconds = 0;
        _videoSegments.clear();
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && !_isPaused) {
          setState(() => _recordedSeconds++);
          if (_recordedSeconds >= 40) _stopRecording();
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
        setState(() => _isPaused = false);
      } else {
        await _controller!.pauseVideoRecording();
        setState(() => _isPaused = true);
      }
    } catch (e) {
      _showError("Pause/Resume xatoligi: $e");
    }
  }

  void _stopRecording() async {
    if (!_isRecording) return;
    _timer?.cancel();
    try {
      if (_isPaused) await _controller!.resumeVideoRecording();
      final XFile lastSegment = await _controller!.stopVideoRecording();
      _videoSegments.add(lastSegment);
      await WakelockPlus.disable();
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
    _zoomLabelTimer?.cancel();
    WakelockPlus.disable();
    _controller?.dispose();
    super.dispose();
  }

  bool _isStepActive(Map<String, dynamic> step) {
    if (_isFrontCamera) return false;
    if (Platform.isIOS) {
      return (step['backLensIndex'] as int) == _currentBackLensIndex;
    }
    return (_currentZoom - (step['value'] as double)).abs() < 0.15;
  }

  String get _currentLensLabel {
    if (_isFrontCamera) return '1×';
    if (_isDraggingLensButton || _showZoomLabel) return _zoomDisplayText;
    for (final step in _zoomSteps) {
      if (_isStepActive(step)) return step['label'] as String;
    }
    return '1×';
  }

  String get _zoomDisplayText {
    if (_currentZoom < 0.55) return '0.5×';
    if (_currentZoom > 0.95 && _currentZoom < 1.05) return '1×';
    if (_currentZoom > 1.95 && _currentZoom < 2.05) return '2×';
    return '${_currentZoom.toStringAsFixed(1)}×';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return const Material(
        color: Colors.white,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final size = MediaQuery.of(context).size;
    final double circleDiameter = size.width * 0.9;
    final double circleLeft = (size.width - circleDiameter) / 2;
    // ✅ SafeArea top + 50
    final double topPadding = MediaQuery.of(context).padding.top + 50;

    final previewSize = _controller!.value.previewSize!;
    final double cameraW = previewSize.height;
    final double cameraH = previewSize.width;
    final double cameraAspect = cameraW / cameraH;
    final double fittedH = circleDiameter / cameraAspect;

    return Material(
      color: Colors.white,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── 1. BLUR ──
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          // ── 2. KAMERA (pinch-to-zoom) ──
          Positioned(
            top: topPadding,
            left: circleLeft,
            width: circleDiameter,
            height: circleDiameter,
            child: Listener(
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              behavior: HitTestBehavior.translucent,
              child: ClipOval(
                child: _isSwitchingCamera
                    ? Container(
                        color: Colors.black26,
                        child: const Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      )
                    : OverflowBox(
                        alignment: Alignment.center,
                        maxWidth: circleDiameter,
                        maxHeight: fittedH,
                        child: SizedBox(
                          width: circleDiameter,
                          height: fittedH,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: cameraW,
                              height: cameraH,
                              child: CameraPreview(_controller!),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),

          // ── 3. BORDER + PROGRESS ──
          Positioned(
            top: topPadding,
            left: circleLeft,
            width: circleDiameter,
            height: circleDiameter,
            child: CustomPaint(
              painter: CircleBorderPainter(
                borderColor: Colors.white,
                borderWidth: 0.9,
                progressColor: _isPaused ? Colors.orange : Colors.red,
                progressWidth: 4.0,
                progress: _isRecording
                    ? (_recordedSeconds / 40).clamp(0.0, 1.0)
                    : 0.0,
              ),
            ),
          ),

          // ── 4. ZOOM LABEL (pinch/drag paytida markazda) ──
          if (_showZoomLabel)
            Positioned(
              top: topPadding + circleDiameter / 2 - 22,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _zoomDisplayText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

          // ── 5. UI CONTROLS ──
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  // ✅ Kamera + top gap
                  SizedBox(
                    height:
                        topPadding -
                        MediaQuery.of(context).padding.top +
                        circleDiameter +
                        16,
                  ),

                  // Timer
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
                          color: Colors.black.withOpacity(0.15),
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

                  const Spacer(),

                  // ✅ ZOOM BUTTON — qizil tugmadan tepada
                  if (!_isFrontCamera)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: GestureDetector(
                        onTap: _zoomSteps.length > 1 ? _toggleLens : null,
                        onLongPressStart: _onLensLongPressStart,
                        onLongPressMoveUpdate: _onLensLongPressMoveUpdate,
                        onLongPressEnd: _onLensLongPressEnd,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: _isDraggingLensButton ? 52 : 44,
                          height: _isDraggingLensButton ? 52 : 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isDraggingLensButton
                                ? Colors.black.withOpacity(0.6)
                                : Colors.black.withOpacity(0.4),
                            border: Border.all(
                              color: _isDraggingLensButton
                                  ? Colors.amber.withOpacity(0.8)
                                  : Colors.white.withOpacity(0.4),
                              width: _isDraggingLensButton ? 2 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _currentLensLabel,
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: _isDraggingLensButton ? 14 : 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // ── Tugmalar ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!_isRecording)
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: _circleButton(
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: _togglePauseResume,
                          child: _circleButton(
                            child: Icon(
                              _isPaused ? Icons.play_arrow : Icons.pause,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      const SizedBox(width: 20),
                      GestureDetector(
                        onTap: _isRecording ? _stopRecording : _startRecording,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                              ),
                            ],
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
                      const SizedBox(width: 20),
                      if (_cameras.length > 1)
                        GestureDetector(
                          onTap: _isSwitchingCamera ? null : _toggleCamera,
                          child: _circleButton(
                            opacity: _isSwitchingCamera ? 0.3 : 1.0,
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
                        )
                      else
                        const SizedBox(width: 60),
                    ],
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({required Widget child, double opacity = 1.0}) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
        child: child,
      ),
    );
  }
}

class CircleBorderPainter extends CustomPainter {
  final Color borderColor;
  final double borderWidth;
  final Color progressColor;
  final double progressWidth;
  final double progress;

  CircleBorderPainter({
    required this.borderColor,
    required this.borderWidth,
    this.progressColor = Colors.red,
    this.progressWidth = 4.0,
    this.progress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final borderRadius = size.width / 2 - borderWidth / 2;
    final borderPaint = Paint()
      ..color = borderColor.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawCircle(center, borderRadius, borderPaint);

    if (progress > 0) {
      final progressRadius = size.width / 2 - progressWidth / 2;
      final trackPaint = Paint()
        ..color = Colors.white.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = progressWidth;
      canvas.drawCircle(center, progressRadius, trackPaint);
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = progressWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: progressRadius),
        -3.14159 / 2,
        2 * 3.14159 * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(CircleBorderPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.progressWidth != progressWidth ||
        oldDelegate.progress != progress;
  }
}
