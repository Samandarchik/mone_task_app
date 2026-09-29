import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class VersionChecker {
  static const String _endpoint =
      "https://version.uzaidev.uz/health?appName=task_mone_app";

  static const String fallbackAppStoreUrl =
      "https://apps.apple.com/us/app/task-app-mone/id6756741172";
  static const String fallbackPlayStoreUrl =
      "https://play.google.com/store/apps/details?id=com.example.app";

  /// 🔹 Versiyani tekshiradi:
  /// agar backend versiyasi katta bo‘lsa → update majburiy
  static Future<bool> checkVersion(BuildContext context) async {
    try {
      final response = await Dio().get(
        _endpoint,
        options: Options(validateStatus: (_) => true),
      );
      if (response.statusCode != 200) {
        debugPrint("⚠️ Server status: ${response.statusCode}");
        return false;
      }

      final decoded = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      final data = decoded['data'];
      if (data == null) return false;

      final iosVersion = data['iosVersion']?.toString();
      final androidVersion = data['androidVersion']?.toString();
      final appStoreUrl = (data['appstoreUrl'] ?? fallbackAppStoreUrl)
          .toString();
      final playStoreUrl = (data['playstoreUrl'] ?? fallbackPlayStoreUrl)
          .toString();

      if (iosVersion == null || androidVersion == null) return false;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version.trim();

      final latestVersion = Platform.isIOS
          ? iosVersion.trim()
          : androidVersion.trim();
      final storeUrl = Platform.isIOS ? appStoreUrl : playStoreUrl;

      debugPrint("📱 Current version: $currentVersion");
      debugPrint("🆕 Backend version: $latestVersion");

      final requiresUpdate = _isNewerVersion(latestVersion, currentVersion);

      debugPrint("🔍 Update needed: $requiresUpdate");

      if (requiresUpdate) {
        _showUpdateDialog(context, storeUrl);
        return true;
      }

      return false;
    } catch (e) {
      debugPrint("❌ Version check error: $e");
      return false;
    }
  }

  /// 🔹 Versiyalarni solishtirish:
  /// agar latest > current → true (update kerak)
  /// agar latest <= current → false
  static bool _isNewerVersion(String latest, String current) {
    final latestParts = latest
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final currentParts = current
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

    final maxLength = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;

    for (int i = 0; i < maxLength; i++) {
      final latestPart = i < latestParts.length ? latestParts[i] : 0;
      final currentPart = i < currentParts.length ? currentParts[i] : 0;

      if (latestPart > currentPart) return true; // yangi versiya
      if (latestPart < currentPart) return false; // eski emas
    }

    return false; // teng bo‘lsa update kerak emas
  }

  static void _showUpdateDialog(BuildContext context, String storeUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.system_update_rounded,
              color: AppColors.primary,
              size: 30,
            ),
          ),
          title: Text(tr('Yangi versiya mavjud'), textAlign: TextAlign.center),
          content: Text(
            tr(
              "Ilovadan foydalanishni davom ettirish uchun uni yangilang. Bu bir necha daqiqa oladi.",
            ),
            textAlign: TextAlign.center,
          ),
          actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: Icon(Icons.download_rounded),
                onPressed: () async {
                  final uri = Uri.parse(storeUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                label: Text(tr('Yangilash')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
