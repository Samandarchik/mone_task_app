import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: VideoNotePage(),
    );
  }
}

class VideoNotePage extends StatefulWidget {
  const VideoNotePage({super.key});

  @override
  State<VideoNotePage> createState() => _VideoNotePageState();
}

class _VideoNotePageState extends State<VideoNotePage> {
  CameraController? _cameraController;
  VideoPlayerController? _videoController;
  bool isRecording = false;
  bool isCameraReady = false;

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  Future<void> initCamera() async {
    /// 1. Permission so‘rash
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      debugPrint("Permission berilmadi");
      return;
    }

    /// 2. Kamera borligini tekshirish
    if (cameras.isEmpty) {
      debugPrint("Kamera topilmadi");
      return;
    }

    /// 3. Front bo‘lsa oladi, bo‘lmasa birinchisi
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
    });
  }

  Future<void> startRecord() async {
    if (!isCameraReady) return;
    await _cameraController!.startVideoRecording();
    setState(() => isRecording = true);
  }

  Future<void> stopRecord() async {
    if (!isRecording) return;

    final file = await _cameraController!.stopVideoRecording();

    _videoController?.dispose();
    _videoController = VideoPlayerController.file(File(file.path));

    await _videoController!.initialize();
    _videoController!
      ..setLooping(true)
      ..play();

    setState(() => isRecording = false);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isCameraReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          /// Aylana preview
          ClipOval(
            child: SizedBox(
              width: 220,
              height: 220,
              child: _videoController != null
                  ? VideoPlayer(_videoController!)
                  : CameraPreview(_cameraController!),
            ),
          ),

          const SizedBox(height: 40),

          /// Telegram style tugma
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

          const SizedBox(height: 16),
          const Text(
            "Bosib turing – yozadi\nQo‘yib yuboring – to‘xtaydi",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
