import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:mone_task_app/worker/ui/recorder_camera.dart';
import 'package:mone_task_app/worker/ui/video_pervi.dart';

/// Video kamida shuncha soniya bo'lishi shart (kartada ham ko'rsatiladi)
const int kMinVideoSeconds = 8;

class TelegramStyleVideoRecorder extends StatefulWidget {
  final int taskId;

  const TelegramStyleVideoRecorder({super.key, required this.taskId});

  @override
  State<TelegramStyleVideoRecorder> createState() =>
      _TelegramStyleVideoRecorderState();
}

class _TelegramStyleVideoRecorderState extends State<TelegramStyleVideoRecorder>
    with WidgetsBindingObserver {
  RecorderCamera? _camera;
  List<CameraDescription> _cameras = [];
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isInitialized = false;
  bool _isSwitchingCamera = false;

  /// To'xtatish so'rovi yuborilgan, fayl hali yopilmoqda (kuchsiz telefonda
  /// bir necha soniya). Bu vaqtda pauza yoki kamera almashtirish xato beradi.
  bool _isStopping = false;

  /// Yozish so'rovi yuborilgan, kamera hali boshlamagan
  bool _isStarting = false;

  /// Ilova yig'ilgan: yozuv yopiladi, ko'rish ekrani qaytganda ochiladi
  bool _inBackground = false;
  bool _previewOnResume = false;
  bool _isFrontCamera = false;
  int _recordedSeconds = 0;
  Timer? _timer;

  /// Video kamida shuncha soniya bo'lishi shart
  static const int _minSeconds = kMinVideoSeconds;

  /// Erta to'xtatishga urinilganda taymer bir lahza qizil bo'ladi
  bool _warnTooShort = false;
  Timer? _warnTimer;

  bool get _tooShort => _isRecording && _recordedSeconds < _minSeconds;

  /// Kamera ochilmasa (masalan iOS simulatorda kamera yo'q) — shu xabar
  /// yopish tugmasi bilan ko'rsatiladi, cheksiz yuklanish o'rniga.
  String? _cameraError;

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

  static bool get _isWindows => Platform.isWindows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  /// Fonda kamera uziladi va yozuv o'zicha tugaydi, plagin esa buni bilmay
  /// eski yozuvni eslab qoladi (keyingisi jim boshlanmaydi). Shu sabab yozuv
  /// fonga o'tishda shu yerda to'g'ri yopiladi.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _inBackground = true;
      if (_isRecording) _stopRecording(background: true);
    } else if (state == AppLifecycleState.resumed) {
      _inBackground = false;
      if (_previewOnResume) {
        _previewOnResume = false;
        _openPreview();
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = "Камера не найдена");
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
      if (mounted) setState(() => _cameraError = "Ошибка камеры: $e");
    }
  }

  /// Faqat debug: kamerasiz qurilmada (simulator) galereyadan video tanlab
  /// yuborish oqimini sinash. Minimal davomiylik bu yerda ham tekshiriladi.
  Future<void> _pickFromGallery() async {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final controller = VideoPlayerController.file(File(file.path));
    try {
      await controller.initialize();
      if (controller.value.duration < const Duration(seconds: _minSeconds)) {
        if (mounted) {
          setState(
            () => _cameraError =
                "Видео должно быть не короче $_minSeconds секунд",
          );
        }
        return;
      }
    } finally {
      controller.dispose();
    }
    if (mounted) Navigator.of(context).pop(file);
  }

  Widget _buildCameraUnavailable() {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                size: 56,
                color: Colors.white70,
              ),
              const SizedBox(height: 16),
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 28),
              if (kDebugMode) ...[
                FilledButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text("Выбрать видео (тест)"),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                child: const Text("Закрыть"),
              ),
            ],
          ),
        ),
      ),
    );
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
    await _camera?.dispose();
    _camera = RecorderCamera(_cameras[cameraIndex]);
    await _camera!.initialize();
    // Windows kamerasi (camera_windows) zoom va pauzani qo'llamaydi
    if (_isWindows) return;
    _minZoom = await _camera!.minZoom();
    final deviceMax = await _camera!.maxZoom();
    _maxZoom = deviceMax.clamp(_minZoom, 16.0);
    _currentZoom = (1.0).clamp(_minZoom, _maxZoom);
    await _camera!.setZoom(_currentZoom);
  }

  Future<void> _toggleLens() async {
    if (_isSwitchingCamera || _isStarting || _isStopping) return;
    if (_isPaused || _isFrontCamera) return;
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
        await _camera!.pause();
        final seg = await _camera!.stop();
        _videoSegments.add(seg);
      }
      final cameraIdx = _findCameraIndexForLens(lensType);
      await _openCamera(cameraIdx);
      _currentBackLensIndex = backLensIndex;
      if (_isRecording && !_isPaused) {
        await _camera!.start();
      }
      if (mounted) setState(() => _isSwitchingCamera = false);
    } catch (e) {
      if (mounted) setState(() => _isSwitchingCamera = false);
      _showError("Ошибка при смене объектива: $e");
    }
    if (_inBackground) _stopRecording(background: true);
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2 || _isSwitchingCamera) return;
    if (_isStarting || _isStopping) return;
    // Pauzadagi yozuv kamera yopilganda yo'qoladi
    if (_isPaused) return;
    setState(() => _isSwitchingCamera = true);
    try {
      if (_isRecording && !_isPaused) {
        await _camera!.pause();
        final seg = await _camera!.stop();
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
        await _camera!.start();
      }
      if (mounted) setState(() => _isSwitchingCamera = false);
    } catch (e) {
      if (mounted) setState(() => _isSwitchingCamera = false);
      _showError("Ошибка при смене камеры: $e");
    }
    if (_inBackground) _stopRecording(background: true);
  }

  void _setZoom(double zoom) {
    if (_isWindows) return;
    if (_camera == null || !_camera!.isReady) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    _currentZoom = clamped;
    _camera!.setZoom(_currentZoom);
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
    if (_pointers.length < 2 || _isWindows) return;
    if (_camera == null || !_camera!.isReady) return;
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
    _camera!.setZoom(_currentZoom);
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
    if (_camera == null || !_camera!.isReady) return;
    if (_isRecording || _isStarting || _isSwitchingCamera) return;
    setState(() => _isStarting = true);
    try {
      await _camera!.start();
      await WakelockPlus.enable();
      if (!mounted) return;
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
      _showError("Не удалось начать запись: $e");
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  void _togglePauseResume() async {
    if (!_isRecording || _isStopping || _isSwitchingCamera) return;
    if (!_camera!.isRecording) return;
    try {
      if (_isPaused) {
        await _camera!.resume();
        setState(() => _isPaused = false);
      } else {
        await _camera!.pause();
        setState(() => _isPaused = true);
      }
    } catch (e) {
      _showError("Ошибка паузы/возобновления: $e");
    }
  }

  /// [background] — ilova fonga o'tdi: kalta yozuv ham yopiladi, lekin
  /// yuborish uchun saqlanmaydi.
  void _stopRecording({bool background = false}) async {
    if (!_isRecording || _isStopping || _isSwitchingCamera) return;
    if (_tooShort && !background) {
      HapticFeedback.heavyImpact();
      _warnTimer?.cancel();
      setState(() => _warnTooShort = true);
      _warnTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _warnTooShort = false);
      });
      return;
    }
    _timer?.cancel();
    setState(() => _isStopping = true);
    try {
      // Kamera almashishda xato bo'lsa yozuv yo'q — tayyor bo'laklar qoladi
      if (_camera!.isRecording) {
        if (_isPaused) await _camera!.resume();
        _videoSegments.add(await _camera!.stop());
      }
      await WakelockPlus.disable();
      if (!mounted) return;
      final tooShort = _recordedSeconds < _minSeconds;
      setState(() {
        _isRecording = false;
        _isPaused = false;
        _isStopping = false;
      });
      if (background && tooShort) {
        setState(() {
          _videoSegments.clear();
          _recordedSeconds = 0;
        });
        _showError("Запись прервана: приложение было свёрнуто");
        return;
      }
      if (_inBackground) {
        _previewOnResume = true;
        return;
      }
      await _openPreview();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isPaused = false;
          _isStopping = false;
        });
      }
      _showError("Ошибка при сохранении видео: $e");
    }
  }

  Future<void> _openPreview() async {
    if (_videoSegments.isEmpty || !mounted) return;
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoPreviewScreen(
          videoSegments: _videoSegments.map((e) => e.path).toList(),
          taskId: widget.taskId,
        ),
      ),
    );
    if (!mounted || result is! Map) return;
    if (result['action'] == 'send') {
      Navigator.of(context).pop(_videoSegments);
    } else if (result['action'] == 'retake') {
      setState(() {
        _videoSegments.clear();
        _recordedSeconds = 0;
      });
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
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _warnTimer?.cancel();
    _zoomLabelTimer?.cancel();
    WakelockPlus.disable();
    _camera?.dispose();
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
    if (_cameraError != null) return _buildCameraUnavailable();
    if (!_isInitialized || _camera == null) {
      return Material(
        color: Colors.black,
        child: Stack(
          children: [
            const Center(child: CircularProgressIndicator(color: Colors.white)),
            SafeArea(
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
              ),
            ),
          ],
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final mediaPadding = MediaQuery.of(context).padding;
    // Pastdagi tugmalar (record + zoom + bottom gap) uchun zarur joy
    const double bottomControlsHeight = 80 + 16 + 44 + 16 + 50;
    final double topPadding = mediaPadding.top + 50;
    final double availableHeight =
        size.height - topPadding - mediaPadding.bottom - bottomControlsHeight;
    // iPad/landshaftda aylana ekranga sig'sin: width va height ichida kichigi
    // tanlanadi, planshetda esa maksimal 680pt bilan cheklanadi
    final bool isTablet = size.shortestSide >= 600;
    final double maxCircle = isTablet ? 680.0 : double.infinity;
    final double circleDiameter = [
      size.width * 0.9,
      availableHeight,
      maxCircle,
    ].reduce((a, b) => a < b ? a : b);
    final double circleLeft = (size.width - circleDiameter) / 2;
    final double circleTop = topPadding;

    return PopScope(
      // Yozish paytida orqaga bosilsa video jimgina yo'qolardi
      canPop: (!_isRecording && !_isStarting) || _isStopping,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. AYLANA ICHIDA KAMERA ──
            // Kadrning markaziy kvadrati ko'rsatiladi: aylanada nima ko'rinsa,
            // videoga ham o'sha tushadi. Pinch zoom butun ekranda ishlaydi.
            Positioned.fill(
              child: Listener(
                onPointerDown: _handlePointerDown,
                onPointerMove: _handlePointerMove,
                onPointerUp: _handlePointerUp,
                behavior: HitTestBehavior.translucent,
                child: Stack(
                  children: [
                    Positioned(
                      top: circleTop,
                      left: circleLeft,
                      width: circleDiameter,
                      height: circleDiameter,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Native preview almashishda ham turadi: kamera shu
                          // ko'rinishga ulanadi va yozish darhol davom etadi
                          if (_camera!.isReady)
                            ClipOval(child: _camera!.buildPreview()),
                          if (_isSwitchingCamera)
                            const Center(
                              child: CircularProgressIndicator.adaptive(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── 2. BORDER + PROGRESS ──
            Positioned(
              top: circleTop,
              left: circleLeft,
              width: circleDiameter,
              height: circleDiameter,
              child: IgnorePointer(
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
            ),

            // ── 3. ZOOM LABEL (pinch/drag paytida markazda) ──
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

            // ── 4. UI CONTROLS ──
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

                    const Spacer(),

                    _isRecording ? _recordTimerPill() : _minDurationHint(),

                    // ✅ ZOOM BUTTON — qizil tugmadan tepada
                    if (!_isFrontCamera && !_isWindows)
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
                        else if (_isWindows)
                          const SizedBox(width: 60)
                        else
                          GestureDetector(
                            onTap: _togglePauseResume,
                            child: _circleButton(
                              opacity: _isStopping ? 0.3 : 1.0,
                              child: Icon(
                                _isPaused ? Icons.play_arrow : Icons.pause,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                        const SizedBox(width: 20),
                        GestureDetector(
                          key: const ValueKey('record_button'),
                          onTap: _isRecording
                              ? _stopRecording
                              : _startRecording,
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
                                  color: _tooShort
                                      ? Colors.red.withValues(alpha: 0.45)
                                      : Colors.red,
                                  borderRadius: BorderRadius.circular(
                                    _isRecording ? 8 : 40,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        if (_cameras.length > 1 &&
                            !(_isWindows && _isRecording))
                          GestureDetector(
                            onTap: _isSwitchingCamera ? null : _toggleCamera,
                            child: _circleButton(
                              opacity: _isSwitchingCamera || _isPaused
                                  ? 0.3
                                  : 1.0,
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
      ),
    );
  }

  String _mmss(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  /// Yozish boshlanmasidan oldin — minimal davomiylik eslatmasi
  Widget _minDurationHint() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 16, color: Colors.white),
            SizedBox(width: 6),
            Text(
              'Видео минимум $kMinVideoSeconds сек',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Yozish vaqti + minimal davomiylik ko'rsatkichi
  Widget _recordTimerPill() {
    final short = _tooShort;
    final color = _warnTooShort
        ? Colors.red
        : (short ? Colors.black.withValues(alpha: 0.55) : Colors.green);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              short ? Icons.timer_outlined : Icons.check_circle_rounded,
              size: 16,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              short
                  ? '${_mmss(_recordedSeconds)} · мин. ${_mmss(_minSeconds)}'
                  : _mmss(_recordedSeconds),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
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
