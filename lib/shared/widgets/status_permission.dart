import 'package:flutter/material.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';

/// Sariq «Р» — faqat Ревизор, qizil «А» — faqat Админ.
/// Ruxsat bo'lmasa xabar matni qaytadi, aks holda null.
String? statusDeniedMessage(int level) {
  final role = sl<TokenStorage>().getUserData()?.role;
  if (level == 2 && role == 'super_admin') {
    return 'Это разрешено только ревизору — у супер админа нет доступа';
  }
  if (level == 1 && role == 'checker') {
    return 'Ревизору нельзя оставлять голос от имени админа';
  }
  return null;
}

/// Ruxsat bo'lsa true; bo'lmasa SnackBar ko'rsatib false qaytaradi.
bool checkStatusPermission(BuildContext context, int level) {
  final message = statusDeniedMessage(level);
  if (message == null) return true;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  return false;
}

/// Status doirasi ichidagi harf: 2 → «Р», 1 → «А».
String? statusLetter(int level) => switch (level) {
  2 => 'Р',
  1 => 'А',
  _ => null,
};
