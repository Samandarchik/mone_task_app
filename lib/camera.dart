import 'dart:ui'; // Muhim!
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:mone_task_app/worker/model/response_task_model.dart';
import 'package:mone_task_app/worker/service/task_worker_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

/// Telegram uslubidagi aylanma video recorder dialog
class TelegramVideoRecorder extends StatefulWidget {
  final int taskId;
  final int maxDuration;

  const TelegramVideoRecorder({
    super.key,
    required this.maxDuration,
    required this.taskId,
  });

  /// Dialog ochishdan oldin permission tekshirish
  static Future<XFile?> show(
    BuildContext context, {
    required int taskId,
    required int maxDuration,
  }) async {
    // iOS va Android uchun permission so'rash
    final statuses = await [Permission.camera, Permission.microphone].request();

    // Permission tekshirish
    if (statuses[Permission.camera] != PermissionStatus.granted ||
        statuses[Permission.microphone] != PermissionStatus.granted) {
      if (!context.mounted) return null;

      // iOS uchun Settings ga yo'naltirish
      final shouldOpenSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ruxsat kerak'),
          content: const Text(
            'Video yozish uchun kamera va mikrofon ruxsati kerak. '
            'Sozlamalar orqali ruxsat bering.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Bekor qilish'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sozlamalar'),
            ),
          ],
        ),
      );

      if (shouldOpenSettings == true) {
        await openAppSettings();
      }
      return null;
    }

    // Permission berilgan bo'lsa, dialogni ochish
    if (!context.mounted) return null;

    final result = await showDialog<XFile?>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          TelegramVideoRecorder(taskId: taskId, maxDuration: maxDuration),
    );

    return result;
  }

  @override
  State<TelegramVideoRecorder> createState() => _TelegramVideoRecorderState();
}

class _TelegramVideoRecorderState extends State<TelegramVideoRecorder>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  VideoPlayerController? _videoController;
  AnimationController? _recordAnimationController;

  bool isRecording = false;
  bool isCameraReady = false;
  bool isFrontCamera = true;
  int _secondsElapsed = 0;
  Timer? _timer;
  XFile? recordedVideo;
  List<CameraDescription> cameras = [];
  TaskWorkerService taskWorkerService = TaskWorkerService();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _recordAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      // Kameralarni olish
      cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() {
          _errorMessage = "Qurilmada kamera topilmadi";
        });
        return;
      }

      // Front kamerani topish
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      await _setupCamera(camera);
    } catch (e) {
      debugPrint("Kamera xatosi: $e");
      setState(() {
        _errorMessage = "Kamera xatosi: $e";
      });
    }
  }

  Future<void> _setupCamera(CameraDescription camera) async {
    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        isCameraReady = true;
        isFrontCamera = camera.lensDirection == CameraLensDirection.front;
      });
    } catch (e) {
      debugPrint("Kamera initialize xatosi: $e");
      setState(() {
        _errorMessage = "Kamera ishga tushmadi: $e";
      });
    }
  }

  Future<void> toggleCamera() async {
    if (!isCameraReady || cameras.length < 2 || recordedVideo != null) return;

    if (isRecording) {
      await stopRecord();
      return;
    }

    setState(() {
      isCameraReady = false;
    });

    await _cameraController?.dispose();

    final camera = cameras.firstWhere(
      (c) =>
          c.lensDirection ==
          (isFrontCamera
              ? CameraLensDirection.back
              : CameraLensDirection.front),
      orElse: () => cameras.first,
    );

    await _setupCamera(camera);
  }

  Future<void> startRecord() async {
    if (!isCameraReady || isRecording || _cameraController == null) return;

    try {
      await _cameraController!.startVideoRecording();

      setState(() {
        isRecording = true;
        _secondsElapsed = 0;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _secondsElapsed++;
        });

        if (_secondsElapsed >= widget.maxDuration) {
          stopRecord();
        }
      });
    } catch (e) {
      debugPrint("Video yozish xatosi: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Video yozish boshlanmadi: $e")));
      }
    }
  }

  Future<void> stopRecord() async {
    if (!isRecording || _cameraController == null) return;

    _timer?.cancel();

    try {
      if (!_cameraController!.value.isRecordingVideo) {
        setState(() => isRecording = false);
        return;
      }

      final file = await _cameraController!.stopVideoRecording();
      recordedVideo = file;

      _videoController?.dispose();
      _videoController = VideoPlayerController.file(File(file.path));

      await _videoController!.initialize();
      _videoController!
        ..setLooping(true)
        ..play();

      if (mounted) {
        setState(() => isRecording = false);
      }
    } catch (e) {}
  }

  void _cancel() {
    _timer?.cancel();
    Navigator.pop(context, null);
  }

  void _sendVideo() {
    _timer?.cancel();
    if (recordedVideo != null) {
      taskWorkerService.completeTask(
        RequestTaskModel(id: widget.taskId, file: recordedVideo),
      );
      Navigator.pop(context, recordedVideo);
    }
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordAnimationController?.dispose();
    _cameraController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Dialog(
        backgroundColor: Colors.black,
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 60),
              const SizedBox(height: 20),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _cancel, child: const Text('Yopish')),
            ],
          ),
        ),
      );
    }

    if (!isCameraReady) {
      return const Dialog(
        backgroundColor: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator.adaptive(),
              SizedBox(height: 20),
              Text(
                'Kamera tayyorlanmoqda...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // 🔥 BLUR BACKGROUND
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: Colors.black.withOpacity(0.3), // Yengil qoraytirish
              ),
            ),
          ),

          // 🔵 Asosiy UI
          Container(
            width: double.infinity,
            height: double.infinity,
            child: Stack(
              children: [
                Center(child: _buildCircularPreview()),

                _buildTopBar(),

                _buildBottomControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularPreview() {
    // Ekran o'lchamlarini olish
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Aylana o'lchami - ekranning kichik tomoniga moslashadi
    final circleSize = screenWidth < screenHeight
        ? screenWidth * 0.8
        : screenHeight * 0.8;

    return Container(
      width: circleSize,
      height: circleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isRecording ? Colors.red : Colors.white,
          width: 4,
        ),
      ),
      child: ClipOval(
        child: OverflowBox(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              height: circleSize / _cameraController!.value.aspectRatio,
              child: _videoController != null && recordedVideo != null
                  ? VideoPlayer(_videoController!)
                  : CameraPreview(_cameraController!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 50,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Close button
            IconButton(
              onPressed: _cancel,
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
            ),

            // Timer with animation
            if (isRecording || _secondsElapsed > 0)
              AnimatedBuilder(
                animation: _recordAnimationController!,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isRecording
                          ? Colors.red.withOpacity(
                              0.7 + (_recordAnimationController!.value * 0.3),
                            )
                          : Colors.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        if (isRecording)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Text(
                          _formatTime(_secondsElapsed),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              )
            else
              const SizedBox.shrink(),

            // Camera flip button
            if (recordedVideo == null && cameras.length > 1)
              IconButton(
                onPressed: toggleCamera,
                icon: const Icon(
                  Icons.flip_camera_ios,
                  color: Colors.white,
                  size: 30,
                ),
              )
            else
              const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 50,
      left: 0,
      right: 0,
      child: Column(
        children: [
          // Progress indicator
          if (isRecording)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _secondsElapsed / widget.maxDuration,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                  minHeight: 6,
                ),
              ),
            ),

          const SizedBox(height: 40),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Retake button
              if (recordedVideo != null)
                _buildActionButton(
                  onTap: () {
                    setState(() {
                      _videoController?.dispose();
                      _videoController = null;
                      recordedVideo = null;
                      _secondsElapsed = 0;
                    });
                  },
                  icon: Icons.refresh,
                  color: Colors.white24,
                  size: 60,
                ),

              if (recordedVideo != null) const SizedBox(width: 40),

              // Record/Stop button (Telegram style)
              if (recordedVideo == null)
                GestureDetector(
                  onTap: () async {
                    if (!isRecording) {
                      await startRecord();
                    } else {
                      await stopRecord();
                    }
                  },
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: isRecording ? 30 : 60,
                        height: isRecording ? 30 : 60,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(
                            isRecording ? 6 : 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (recordedVideo != null) const SizedBox(width: 40),

              // Send button
              if (recordedVideo != null)
                _buildActionButton(
                  onTap: _sendVideo,
                  icon: Icons.check,
                  color: Colors.green,
                  size: 60,
                ),
            ],
          ),

          const SizedBox(height: 20),

          // Instruction text
          Text(
            recordedVideo != null
                ? "Qayta yozish yoki yuborish"
                : isRecording
                ? "To'xtatish uchun bosing"
                : "Boshlash uchun bosing",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback onTap,
    required IconData icon,
    required Color color,
    required double size,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}
