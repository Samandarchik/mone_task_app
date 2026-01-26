import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'video_preview_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isRecording = false;
  bool _isSwitchingCamera = false;
  bool _isLoading = true;
  bool _isError = false;

  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;

  // Video qismlarini saqlash uchun
  List<String> _videoParts = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> requestPermissions() async {
    await Permission.camera.request();
    await Permission.microphone.request();
  }

  Future<void> _initializeCamera() async {
    await requestPermissions();

    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        _isError = true;
        _isLoading = false;
        if (mounted) setState(() {});
        return;
      }

      // Orqa kamerani topish
      final backCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _currentCameraIndex = _cameras.indexOf(backCamera);

      _controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: true,
      );

      await _controller!.initialize();
      _isLoading = false;
    } catch (e) {
      debugPrint('Kamera initsializatsiya xatosi: $e');
      _isError = true;
      _isLoading = false;
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _switchToCamera(int cameraIndex) async {
    if (_cameras.isEmpty || cameraIndex >= _cameras.length) return;

    final camera = _cameras[cameraIndex];
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Kamera initsializatsiya xatosi: $e');
    }
  }

  Future<void> _startVideoRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      await _controller!.startVideoRecording();
      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      debugPrint('Video yozish boshlanishida xato: $e');
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_controller == null || !_controller!.value.isRecordingVideo) return;

    try {
      final video = await _controller!.stopVideoRecording();

      // Video qismini ro'yxatga qo'shish
      _videoParts.add(video.path);

      setState(() {
        _isRecording = false;
      });

      debugPrint('Video qismi saqlandi: ${video.path}');
    } catch (e) {
      debugPrint('Video to\'xtatishda xato: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_isSwitchingCamera || _cameras.length < 2) return;

    setState(() {
      _isSwitchingCamera = true;
    });

    bool wasRecording = _isRecording;

    // Agar video yozilayotgan bo'lsa, to'xtatish
    if (wasRecording) {
      await _stopVideoRecording();
    }

    // Eski controllerni tozalash
    await _controller?.dispose();

    // Keyingi kameraga o'tish
    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;

    // Yangi kamerani ishga tushirish
    await _switchToCamera(_currentCameraIndex);

    // Agar video yozilayotgan bo'lsa, qaytadan boshlash
    if (wasRecording) {
      await _startVideoRecording();
    }

    setState(() {
      _isSwitchingCamera = false;
    });
  }

  Future<void> _finishRecording() async {
    if (_isRecording) {
      await _stopVideoRecording();
    }

    if (_videoParts.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Video yozilmagan')));
      return;
    }

    // Agar faqat bitta qism bo'lsa, uni ko'rsatish
    if (_videoParts.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPreviewScreen(videoPath: _videoParts[0]),
        ),
      );
      _videoParts.clear();
      return;
    }

    // Agar bir nechta qism bo'lsa, ularni birlashtirish
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Video birlashtirilyapti...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Videolarni birlashtirish
      final mergedPath = await _mergeVideos(_videoParts);

      if (mounted) {
        Navigator.pop(context); // Dialog yopish

        // Video preview ekraniga o'tish
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPreviewScreen(videoPath: mergedPath),
          ),
        );
      }

      // Vaqtinchalik fayllarni o'chirish
      for (var path in _videoParts) {
        try {
          await File(path).delete();
        } catch (e) {
          debugPrint('Faylni o\'chirishda xato: $e');
        }
      }

      _videoParts.clear();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Xato: $e')));
      }
    }
  }

  // Video qismlarini birlashtirish (oddiy usul - fayllarni ketma-ket yozish)
  Future<String> _mergeVideos(List<String> videoPaths) async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${directory.path}/merged_video_$timestamp.mp4';

    final outputFile = File(outputPath);
    final sink = outputFile.openWrite();

    try {
      for (var videoPath in videoPaths) {
        final file = File(videoPath);
        final bytes = await file.readAsBytes();
        sink.add(bytes);
      }

      await sink.flush();
      await sink.close();

      debugPrint('Video birlashtirildi: $outputPath');
      return outputPath;
    } catch (e) {
      await sink.close();
      throw Exception('Video birlashtirish xatosi: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_isError || _controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Kamera xatosi',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _isError = false;
                  });
                  _initializeCamera();
                },
                child: const Text('Qayta urinish'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Kamera ko'rinishi
          Center(child: CameraPreview(_controller!)),

          // Yuqori panel
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                    if (_isRecording)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'REC',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Pastki boshqaruv paneli
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Kamera almashtirish tugmasi
                    _buildControlButton(
                      icon: Icons.flip_camera_ios,
                      onPressed: _isSwitchingCamera ? null : _switchCamera,
                      size: 50,
                    ),

                    // Yozish/To'xtatish tugmasi
                    GestureDetector(
                      onTap: () async {
                        if (_isRecording) {
                          await _finishRecording();
                        } else {
                          await _startVideoRecording();
                        }
                      },
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: Center(
                          child: Container(
                            width: _isRecording ? 30 : 60,
                            height: _isRecording ? 30 : 60,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(
                                _isRecording ? 8 : 30,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Yakunlash tugmasi (faqat yozish paytida)
                    _isRecording
                        ? _buildControlButton(
                            icon: Icons.check,
                            onPressed: _finishRecording,
                            size: 50,
                          )
                        : const SizedBox(width: 50),
                  ],
                ),
              ),
            ),
          ),

          // Kamera almashish animatsiyasi
          if (_isSwitchingCamera)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required double size,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.2),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
        iconSize: size * 0.5,
      ),
    );
  }
}
