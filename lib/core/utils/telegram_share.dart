import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Faylni to'g'ridan-to'g'ri Telegram ilovasiga yuborish (Android).
/// Boshqa platformalarda yoki Telegram o'rnatilmagan bo'lsa — `false`.
abstract final class TelegramShare {
  static const _channel = MethodChannel('mone/telegram_share');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<bool> isInstalled() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isInstalled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// `true` — Telegram ochildi.
  static Future<bool> shareFile(
    String path, {
    String? text,
    String mime = '*/*',
  }) async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('shareFile', {
            'path': path,
            'text': text,
            'mime': mime,
          }) ??
          false;
    } catch (e) {
      debugPrint('TelegramShare error: $e');
      return false;
    }
  }
}
