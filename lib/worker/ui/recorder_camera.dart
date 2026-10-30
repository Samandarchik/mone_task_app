import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Aylana video uchun yetarli sifat: 40 soniyalik video taxminan 5 MB
const int _kVideoBitrate = 900 * 1000;
const int _kAudioBitrate = 64 * 1000;

/// Aylana kamera: Android'da native (Kotlin, CameraX), qolgan platformalarda
/// `camera` plagini.
abstract class RecorderCamera {
  static bool useNative = !kIsWeb && Platform.isAndroid;

  factory RecorderCamera(CameraDescription description) => useNative
      ? _NativeCamera(description.lensDirection == CameraLensDirection.front)
      : _PluginCamera(description);

  Future<void> initialize();
  Future<void> dispose();

  bool get isReady;
  bool get isRecording;

  Future<void> start();
  Future<XFile> stop();
  Future<void> pause();
  Future<void> resume();

  Future<double> minZoom();
  Future<double> maxZoom();
  Future<void> setZoom(double zoom);

  /// Kvadrat joyni to'ldiruvchi preview — kadrning markaziy qismi
  Widget buildPreview();
}

class _PluginCamera implements RecorderCamera {
  final CameraController _controller;

  _PluginCamera(CameraDescription description)
    : _controller = CameraController(
        description,
        ResolutionPreset.medium,
        fps: 30,
        videoBitrate: _kVideoBitrate,
        audioBitrate: _kAudioBitrate,
        enableAudio: true,
      );

  @override
  Future<void> initialize() => _controller.initialize();
  @override
  Future<void> dispose() => _controller.dispose();
  @override
  bool get isReady =>
      _controller.value.isInitialized && _controller.value.previewSize != null;
  @override
  bool get isRecording => _controller.value.isRecordingVideo;
  @override
  Future<void> start() => _controller.startVideoRecording();
  @override
  Future<XFile> stop() => _controller.stopVideoRecording();
  @override
  Future<void> pause() => _controller.pauseVideoRecording();
  @override
  Future<void> resume() => _controller.resumeVideoRecording();
  @override
  Future<double> minZoom() => _controller.getMinZoomLevel();
  @override
  Future<double> maxZoom() => _controller.getMaxZoomLevel();
  @override
  Future<void> setZoom(double zoom) => _controller.setZoomLevel(zoom);

  @override
  Widget buildPreview() {
    final previewSize = _controller.value.previewSize!;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: previewSize.height,
        height: previewSize.width,
        child: CameraPreview(_controller),
      ),
    );
  }
}

class _NativeCamera implements RecorderCamera {
  static const _channel = MethodChannel('circle_camera');

  final bool _front;
  bool _recording = false;

  _NativeCamera(this._front);

  @override
  Future<void> initialize() async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    if (statuses[Permission.camera]?.isGranted != true) {
      throw CameraException('permission', 'Нет доступа к камере');
    }
    // Natija preview ulangach keladi, shu sabab kutilmaydi — xato start'da chiqadi
    _channel.invokeMethod('open', {'front': _front}).catchError((Object e) {
      debugPrint('circle_camera open: $e');
    });
  }

  @override
  Future<void> dispose() async {
    _recording = false;
    await _channel.invokeMethod('close');
  }

  @override
  bool get isReady => true;
  @override
  bool get isRecording => _recording;

  @override
  Future<void> start() async {
    await _channel.invokeMethod('start');
    _recording = true;
  }

  @override
  Future<XFile> stop() async {
    try {
      final path = await _channel.invokeMethod<String>('stop');
      return XFile(path!);
    } finally {
      _recording = false;
    }
  }

  @override
  Future<void> pause() => _channel.invokeMethod('pause');
  @override
  Future<void> resume() => _channel.invokeMethod('resume');

  Future<List<double>> _zoomRange() async {
    final range = await _channel.invokeListMethod<double>('zoomRange');
    return range!;
  }

  @override
  Future<double> minZoom() async => (await _zoomRange()).first;
  @override
  Future<double> maxZoom() async => (await _zoomRange()).last;
  @override
  Future<void> setZoom(double zoom) =>
      _channel.invokeMethod('setZoom', {'zoom': zoom});

  @override
  Widget buildPreview() => AndroidView(
    viewType: 'circle_camera_preview',
    creationParamsCodec: const StandardMessageCodec(),
    gestureRecognizers: const {},
  );
}
