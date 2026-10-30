import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mone_task_app/worker/ui/telegram_style_video_recorder.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// CameraX + camera_android_camerax xatti-harakati:
/// - close() dan keyin pause/resume IllegalStateException beradi
/// - plaginning `recording` maydoni finalize'gacha null bo'lmaydi
/// - recording bor paytda start jim o'tkazib yuboriladi
/// - dispose kamerani uzadi, lekin `recording` eskicha qoladi
class FakeCamera extends CameraPlatform with MockPlatformInterfaceMixin {
  _Rec? rec;
  int startCalls = 0;
  int startsIgnored = 0;
  int stopCalls = 0;
  int lostRecordings = 0;
  int failNextStart = 0;
  int _nextId = 1;
  int _files = 0;
  Duration stopDelay = const Duration(milliseconds: 600);

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
    CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 270,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings? mediaSettings,
  ) async => _nextId++;

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async => _nextId++;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          720,
          480,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      const Stream.empty();
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>.broadcast().stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      Stream.value(
        const DeviceOrientationChangedEvent(DeviceOrientation.portraitUp),
      );
  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1;
  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 8;
  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {}
  @override
  Future<void> dispose(int cameraId) async {
    if (rec != null) {
      rec!.finalized = true;
      lostRecordings++;
    }
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    startCalls++;
    if (failNextStart > 0) {
      failNextStart--;
      throw PlatformException(code: 'start', message: 'start failed');
    }
    if (rec != null) {
      startsIgnored++;
      return;
    }
    rec = _Rec('/tmp/video_${_files++}.mp4');
    // Plagin VideoRecordEventStart kutadi
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    stopCalls++;
    if (rec == null) {
      throw PlatformException(code: 'videoRecordingFailed');
    }
    rec!.closed = true;
    await Future<void>.delayed(stopDelay);
    final path = rec!.path;
    rec = null;
    return XFile(path);
  }

  void _check() {
    if (rec != null && rec!.closed) {
      throw PlatformException(
        code: 'IllegalStateException',
        message: 'The recording has been stopped.',
      );
    }
  }

  @override
  Future<void> pauseVideoRecording(int cameraId) async => _check();
  @override
  Future<void> resumeVideoRecording(int cameraId) async => _check();
}

class _Rec {
  final String path;
  bool closed = false;
  bool finalized = false;
  _Rec(this.path);
}

class FakeWakelock extends WakelockPlusPlatformInterface
    with MockPlatformInterfaceMixin {
  bool on = false;
  @override
  Future<void> toggle({required bool enable}) async => on = enable;
  @override
  Future<bool> get enabled async => on;
}

class FakeVideoPlayer extends VideoPlayerPlatform
    with MockPlatformInterfaceMixin {
  int _id = 0;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => _id++;
  @override
  Future<int?> create(DataSource dataSource) async => _id++;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 500),
      size: const Size(500, 500),
    ),
  );
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildView(int playerId) => const SizedBox.expand();
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

final _record = find.byKey(const ValueKey('record_button'));

void main() {
  late FakeCamera camera;
  late List<Object?> results;
  late int hostPops;

  setUp(() {
    camera = FakeCamera();
    CameraPlatform.instance = camera;
    VideoPlayerPlatform.instance = FakeVideoPlayer();
    WakelockPlusPlatformInterface.instance = FakeWakelock();
    results = [];
    hostPops = 0;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  final r = await Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (_, _, _) =>
                          const TelegramStyleVideoRecorder(taskId: 1),
                    ),
                  );
                  results.add(r);
                  hostPops++;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(_record, findsOneWidget);
  }

  Future<void> tick(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> startAndRecord(WidgetTester tester, int seconds) async {
    await tester.tap(_record);
    await tester.pump();
    await tick(tester, seconds);
  }

  /// Sinov tugagach taymerlar qolmasin
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  Finder errorText(String part) => find.textContaining(part);

  testWidgets('to\'xtatilayotganda pauza xato bermaydi', (tester) async {
    await open(tester);
    await startAndRecord(tester, 9);
    await tester.tap(_record);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(errorText('Ошибка паузы'), findsNothing);
    expect(camera.stopCalls, 1);
    await leave(tester);
  });

  testWidgets('40 soniyadagi avto-to\'xtashda pauza xato bermaydi', (
    tester,
  ) async {
    await open(tester);
    await startAndRecord(tester, 40);
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byIcon(Icons.pause).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.pause));
    }
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(errorText('Ошибка паузы'), findsNothing);
    await leave(tester);
  });

  testWidgets('to\'xtatish ikki marta bosilsa bir marta ishlaydi', (
    tester,
  ) async {
    await open(tester);
    await startAndRecord(tester, 9);
    await tester.tap(_record);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_record);
    await tester.pump(const Duration(seconds: 1));
    expect(camera.stopCalls, 1);
    await leave(tester);
  });

  testWidgets('kamera almashayotganda pauza xato bermaydi', (tester) async {
    await open(tester);
    await startAndRecord(tester, 3);
    await tester.tap(find.byIcon(Icons.flip_camera_ios));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(errorText('Ошибка'), findsNothing);
    await leave(tester);
  });

  testWidgets('pauzada kamera almashtirish yozuvni yo\'qotmaydi', (
    tester,
  ) async {
    await open(tester);
    await startAndRecord(tester, 9);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.flip_camera_ios));
    await tester.pump(const Duration(seconds: 1));
    expect(camera.lostRecordings, 0);
    await tester.tap(_record);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(errorText('Ошибка'), findsNothing);
    expect(find.byIcon(Icons.send), findsOneWidget);
    await leave(tester);
  });

  testWidgets('yozish paytida orqaga chiqib bo\'lmaydi', (tester) async {
    await open(tester);
    await startAndRecord(tester, 9);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(camera.lostRecordings, 0);
    expect(_record, findsOneWidget);
    await leave(tester);
  });

  testWidgets(
    'ilova yopilganda (8+ s) video saqlanib, qaytganda ko\'rsatiladi',
    (tester) async {
      await open(tester);
      await startAndRecord(tester, 9);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(camera.stopCalls, 1);
      expect(find.byIcon(Icons.send), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.send), findsOneWidget);
      await leave(tester);
    },
  );

  testWidgets(
    'ilova yopilganda (<8 s) yozuv bekor qilinadi, keyingisi ishlaydi',
    (tester) async {
      await open(tester);
      await startAndRecord(tester, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(camera.stopCalls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byIcon(Icons.send), findsNothing);
      await startAndRecord(tester, 9);
      expect(camera.startsIgnored, 0);
      await tester.tap(_record);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.send), findsOneWidget);
      await leave(tester);
    },
  );

  testWidgets('yozish boshlash ikki marta bosilsa bir marta ishlaydi', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(_record);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_record);
    await tester.pump(const Duration(milliseconds: 50));
    await tick(tester, 1);
    expect(camera.startCalls, 1);
    await leave(tester);
  });

  testWidgets('«Отправить» ikki marta bosilsa natija bir marta qaytadi', (
    tester,
  ) async {
    await open(tester);
    await startAndRecord(tester, 9);
    await tester.tap(_record);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.send));
    await tester.tap(find.byIcon(Icons.send), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(hostPops, 1);
    expect(results.single, isA<List<XFile>>());
    expect((results.single as List<XFile>).length, 1);
  });

  testWidgets(
    'kamera almashtirishda start xato bersa, to\'xtatish tiqilib qolmaydi',
    (tester) async {
      await open(tester);
      await startAndRecord(tester, 9);
      camera.failNextStart = 1;
      await tester.tap(find.byIcon(Icons.flip_camera_ios));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(_record);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.send), findsOneWidget);
      await leave(tester);
    },
  );
}
