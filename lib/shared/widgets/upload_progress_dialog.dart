import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Video yuklanayotganda foiz ko'rsatuvchi oyna. [upload] qanday tugamasin
/// (xato bo'lsa ham) oyna yopiladi — xatoni chaqiruvchi o'zi ushlaydi.
Future<T> runWithUploadProgress<T>(
  BuildContext context, {
  required String title,
  required Future<T> Function(ProgressCallback onProgress) upload,
}) async {
  // context yuklash vaqtida yo'qolsa ham oyna yopilishi uchun
  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = ValueNotifier<double>(0);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fayl yetib bordi, server javobi kutilmoqda
              LinearProgressIndicator(value: value >= 1 ? null : value),
              const SizedBox(height: 8),
              Text(value >= 1 ? "Обработка..." : "${(value * 100).round()}%"),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    return await upload((sent, total) {
      if (total > 0) progress.value = sent / total;
    });
  } finally {
    navigator.pop();
    progress.dispose();
  }
}
