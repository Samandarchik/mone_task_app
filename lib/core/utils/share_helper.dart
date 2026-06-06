import 'dart:io';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Task linkini ulashish uchun umumiy helper.
///
/// Windows'da `share_plus` ning native share oynasi ishlamaydi, shuning uchun
/// Windows'da link to'g'ridan-to'g'ri Telegram'ning share oynasiga yuboriladi
/// (`https://t.me/share/url`). Qolgan platformalarda odatdagi tizim share
/// oynasi ochiladi.
Future<void> shareTaskLink({
  required String title,
  required String link,
  Rect? sharePositionOrigin,
}) async {
  if (Platform.isWindows) {
    await _shareToTelegram(title: title, link: link);
    return;
  }

  await Share.share(
    '$title\n$link',
    subject: title,
    sharePositionOrigin: sharePositionOrigin,
  );
}

/// Telegram'ning rasmiy share oynasini ochadi. Telegram Desktop o'rnatilgan
/// bo'lsa, ilova ochiladi; aks holda brauzerda Telegram Web ochiladi.
Future<void> _shareToTelegram({
  required String title,
  required String link,
}) async {
  final telegramUri = Uri.parse(
    'https://t.me/share/url'
    '?url=${Uri.encodeComponent(link)}'
    '&text=${Uri.encodeComponent(title)}',
  );

  await launchUrl(telegramUri, mode: LaunchMode.externalApplication);
}
