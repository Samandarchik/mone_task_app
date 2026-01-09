import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';

/// Telegram uslubidagi video recorder dialog
class VideoRecorderDialog extends StatefulWidget {
  final int maxDuration;

  const VideoRecorderDialog({super.key, required this.maxDuration});

  @override
  State<VideoRecorderDialog> createState() => _VideoRecorderDialogState();
}

class _VideoRecorderDialogState extends State<VideoRecorderDialog> {
  CameraController? _cameraController;
  VideoPlayerController? _videoController;
  bool isRecording = false;
  bool isCameraReady = false;
  bool isFrontCamera = true;
  int _secondsElapsed = 0;
  Timer? _timer;
  XFile? recordedVideo;
  List<CameraDescription> cameras = [];

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  Future<void> initCamera() async {
    // Permission so'rash
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      debugPrint("Permission berilmadi");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Kamera va mikrofon ruxsati kerak!")),
        );
        Navigator.pop(context, null);
      }
      return;
    }

    // Kameralarni olish
    try {
      cameras = await availableCameras();
    } catch (e) {
      debugPrint("Kameralarni olishda xatolik: $e");
      if (mounted) {
        Navigator.pop(context, null);
      }
      return;
    }

    // Kamera borligini tekshirish
    if (cameras.isEmpty) {
      debugPrint("Kamera topilmadi");
      if (mounted) {
        Navigator.pop(context, null);
      }
      return;
    }

    // Front kamerani topish
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: true,
    );

    await _cameraController!.initialize();

    if (!mounted) return;

    setState(() {
      isCameraReady = true;
      isFrontCamera = camera.lensDirection == CameraLensDirection.front;
    });
  }

  Future<void> toggleCamera() async {
    if (!isCameraReady || cameras.length < 2) return;

    setState(() {
      isCameraReady = false;
    });

    await _cameraController?.dispose();

    // Kamera o'zgartirish
    final camera = cameras.firstWhere(
      (c) =>
          c.lensDirection ==
          (isFrontCamera
              ? CameraLensDirection.back
              : CameraLensDirection.front),
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: true,
    );

    await _cameraController!.initialize();

    if (!mounted) return;

    setState(() {
      isCameraReady = true;
      isFrontCamera = !isFrontCamera;
    });
  }

  Future<void> startRecord() async {
    if (!isCameraReady || isRecording) return;

    await _cameraController!.startVideoRecording();

    setState(() {
      isRecording = true;
      _secondsElapsed = 0;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });

      if (_secondsElapsed >= widget.maxDuration) {
        stopRecord();
      }
    });
  }

  Future<void> stopRecord() async {
    if (!isRecording) return;

    _timer?.cancel();

    final file = await _cameraController!.stopVideoRecording();
    recordedVideo = file;

    _videoController?.dispose();
    _videoController = VideoPlayerController.file(File(file.path));

    await _videoController!.initialize();
    _videoController!
      ..setLooping(true)
      ..play();

    setState(() => isRecording = false);
  }

  void _cancel() {
    _timer?.cancel();
    Navigator.pop(context, null);
  }

  void _save() {
    _timer?.cancel();
    Navigator.pop(context, recordedVideo);
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cameraController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isCameraReady) {
      return const Dialog(
        backgroundColor: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Stack(
          children: [
            // Kamera yoki video preview
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 400,
                  height: 400,
                  child: _videoController != null && recordedVideo != null
                      ? VideoPlayer(_videoController!)
                      : CameraPreview(_cameraController!),
                ),
              ),
            ),

            // Top controls
            Positioned(
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
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),

                    // Timer
                    if (isRecording || _secondsElapsed > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _formatTime(_secondsElapsed),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),

                    // Camera switch button
                    if (recordedVideo == null)
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
            ),

            // Bottom controls
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  // Progress indicator
                  if (isRecording)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: LinearProgressIndicator(
                        value: _secondsElapsed / widget.maxDuration,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.red,
                        ),
                        minHeight: 4,
                      ),
                    ),

                  const SizedBox(height: 30),

                  // Main action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Cancel/Retake button
                      if (recordedVideo != null)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _videoController?.dispose();
                              _videoController = null;
                              recordedVideo = null;
                              _secondsElapsed = 0;
                            });
                          },
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white24,
                            ),
                            child: const Icon(
                              Icons.refresh,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),

                      const SizedBox(width: 40),

                      // Record/Stop button
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
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isRecording ? Colors.red : Colors.blue,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            child: Icon(
                              isRecording ? Icons.stop : Icons.videocam,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ),

                      const SizedBox(width: 40),

                      // Send button
                      if (recordedVideo != null)
                        GestureDetector(
                          onTap: _save,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Instruction text
                  Text(
                    recordedVideo != null
                        ? "Qayta yozish yoki yuborish"
                        : (isRecording
                              ? "To'xtatish uchun bosing"
                              : "Boshlash uchun bosing"),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
