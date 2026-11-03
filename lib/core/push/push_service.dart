import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';

/// Firebase konsolidagi `mone-bakery` loyihasi (iOS: GoogleService-Info.plist)
const _iosOptions = FirebaseOptions(
  apiKey: 'AIzaSyA38Au7Exrnp1otuOXaJ0SQCNrS9NYBf9Y',
  appId: '1:67631825847:ios:f7f9f8951b473bbeb15e32',
  messagingSenderId: '67631825847',
  projectId: 'mone-bakery',
  iosBundleId: 'uz.uzaidev.taskapp',
);

/// Firebase'da `com.uzaidev.mone_task_app` Android ilovasi qo'shilgach,
/// google-services.json dagi `mobilesdk_app_id` va `current_key` shu yerga
/// yoziladi. Bo'sh turganda Android'da push o'chiq (WS va Telegram ishlaydi).
const _androidAppId = '';
const _androidApiKey = '';

/// Telefonga keladigan ovozli bildirishnoma (FCM). Windows/macOS'da ishlamaydi.
class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;
  PushService._internal();

  final _demands = StreamController<void>.broadcast();
  bool _started = false;
  String? _token;

  /// Ilova ochiq paytda push keldi yoki bildirishnoma bosildi — talab oynasini
  /// ko'rsatish uchun
  Stream<void> get onDemand => _demands.stream;

  FirebaseOptions? get _options {
    if (Platform.isIOS) return _iosOptions;
    if (Platform.isAndroid && _androidAppId.isNotEmpty) {
      return const FirebaseOptions(
        apiKey: _androidApiKey,
        appId: _androidAppId,
        messagingSenderId: '67631825847',
        projectId: 'mone-bakery',
      );
    }
    return null;
  }

  /// Hisobga kirilgandan keyin chaqiriladi. Xato ilovani to'xtatmasligi kerak:
  /// push ishlamasa ham WS va Telegram qoladi.
  Future<void> register() async {
    final options = _options;
    if (options == null) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      if (!_started) {
        _started = true;
        FirebaseMessaging.onMessage.listen((_) => _demands.add(null));
        FirebaseMessaging.onMessageOpenedApp.listen((_) => _demands.add(null));
        messaging.onTokenRefresh.listen(_saveToken);
      }

      if (Platform.isIOS && !await _waitForApnsToken(messaging)) return;
      final token = await messaging.getToken();
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('Push yoqilmadi: $e');
    }
  }

  /// iOS'da FCM tokeni APNs tokenisiz olinmaydi; u ishga tushgach biroz
  /// kechikib keladi (simulyatorda umuman kelmasligi mumkin).
  Future<bool> _waitForApnsToken(FirebaseMessaging messaging) async {
    for (var i = 0; i < 5; i++) {
      if (await messaging.getAPNSToken() != null) return true;
      await Future.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  Future<void> _saveToken(String token) async {
    try {
      await sl<Dio>().post(
        AppUrls.deviceToken,
        data: {'token': token, 'platform': Platform.operatingSystem},
      );
      _token = token;
    } catch (e) {
      debugPrint('Push token saqlanmadi: $e');
    }
  }

  /// Hisobdan chiqishda — chiqib ketgan odamning telefoniga talab bormasin
  Future<void> unregister() async {
    var token = _token;
    _token = null;
    try {
      // Ro'yxatdan o'tish hali tugamagan yoki saqlash yiqilgan bo'lsa ham
      // serverdagi token o'chishi kerak — aks holda chiqib ketgan odamga
      // talablar borib turadi
      if (token == null && Firebase.apps.isNotEmpty) {
        token = await FirebaseMessaging.instance.getToken();
      }
      if (token == null) return;
      await sl<Dio>().delete(AppUrls.deviceToken, data: {'token': token});
    } catch (e) {
      debugPrint("Push token o'chirilmadi: $e");
    }
  }
}
