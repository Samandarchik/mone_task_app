import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Task linkini ulashish uchun umumiy helper.
///
/// Windows'da `share_plus` ning native share oynasi ishlamaydi, shuning uchun
/// Windows'da link clipboard'ga nusxalanadi (`context` berilsa, SnackBar
/// ko'rsatiladi). Qolgan platformalarda (iOS/Android) odatdagi tizim share
/// oynasi ochiladi.
Future<void> shareTaskLink({
  required String title,
  required String link,
  Rect? sharePositionOrigin,
  BuildContext? context,
}) async {
  if (Platform.isWindows) {
    await Clipboard.setData(ClipboardData(text: link));
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ссылка скопирована'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    return;
  }

  await Share.share(
    '$title\n$link',
    subject: title,
    sharePositionOrigin: sharePositionOrigin,
  );
}
