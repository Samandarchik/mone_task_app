import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Windows ilovasini avtomatik yangilash.
///
/// Versiya ko'tarilib `main` ga push qilinganda GitHub Actions
/// (.github/workflows/windows-release.yml) Windows build'ni yig'ib,
/// `windows-<versiya>-<build>` tegli Release'ga zip qilib qo'yadi.
/// Ilova ochilganda va har [_checkEvery] da shu Release'larni tekshiradi:
/// yangisi bo'lsa so'raydi, yuklab oladi, o'zini almashtirib qayta ochiladi.
class WindowsUpdater {
  static const _releasesUrl =
      'https://api.github.com/repos/Samandarchik/mone_task_app/releases?per_page=20';
  static const tagPrefix = 'windows-';
  static const assetName = 'mone_task_app_windows.zip';
  static const _exeName = 'mone_task_app.exe';
  static const _checkEvery = Duration(hours: 6);

  static GlobalKey<NavigatorState>? _navigatorKey;
  static Timer? _timer;
  static bool _busy = false;

  /// «Позже» bosilgan build — shu ishga tushirishda qayta so'ralmaydi
  static int? _postponedBuild;

  static void start(GlobalKey<NavigatorState> navigatorKey) {
    if (!Platform.isWindows || _timer != null) return;
    _navigatorKey = navigatorKey;
    // Ilova to'liq ochilib olsin
    Future.delayed(const Duration(seconds: 10), check);
    _timer = Timer.periodic(_checkEvery, (_) => check());
  }

  /// Tegdan build raqami: `windows-0.3.8-308` → 308
  static int? buildFromTag(String tag) {
    if (!tag.startsWith(tagPrefix)) return null;
    return int.tryParse(tag.split('-').last);
  }

  /// Tegdan versiya: `windows-0.3.8-308` → 0.3.8
  static String versionFromTag(String tag) {
    final parts = tag.substring(tagPrefix.length).split('-');
    return parts.length > 1 ? parts.first : tag;
  }

  static Future<void> check() async {
    if (_busy) return;
    _busy = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;

      final response = await Dio().get<List<dynamic>>(
        _releasesUrl,
        options: Options(
          headers: {'Accept': 'application/vnd.github+json'},
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      // Eng katta build raqamli Windows release
      Map<String, dynamic>? latest;
      int latestBuild = 0;
      String? zipUrl;
      for (final r in response.data ?? const []) {
        if (r is! Map<String, dynamic>) continue;
        if (r['draft'] == true || r['prerelease'] == true) continue;
        final build = buildFromTag('${r['tag_name']}');
        if (build == null || build <= latestBuild) continue;
        final asset = (r['assets'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .where((a) => a['name'] == assetName)
            .firstOrNull;
        if (asset == null) continue;
        latest = r;
        latestBuild = build;
        zipUrl = '${asset['browser_download_url']}';
      }

      if (latest == null || zipUrl == null) return;
      if (latestBuild <= current || latestBuild == _postponedBuild) return;

      final version = versionFromTag('${latest['tag_name']}');
      final context = _navigatorKey?.currentContext;
      if (context == null || !context.mounted) return;

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.system_update_alt_rounded,
            color: Color(0xFF2563EB),
            size: 36,
          ),
          title: Text("Новая версия $version"),
          content: Text(
            "Сейчас установлена ${info.version}. "
            "Обновить? Программа перезапустится сама.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Позже"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Обновить"),
            ),
          ],
        ),
      );
      if (ok != true) {
        _postponedBuild = latestBuild;
        return;
      }
      if (context.mounted) await _install(context, zipUrl, latestBuild);
    } catch (e) {
      // Internet yo'q yoki GitHub javob bermadi — keyingi tekshiruvda
      debugPrint('Windows yangilanishini tekshirib bo\'lmadi: $e');
    } finally {
      _busy = false;
    }
  }

  static Future<void> _install(
    BuildContext context,
    String zipUrl,
    int build,
  ) async {
    final installDir = File(Platform.resolvedExecutable).parent;

    // Dastur papkasiga yozib bo'ladimi (Program Files bo'lsa — yo'q)
    try {
      final probe = File('${installDir.path}\\.update_probe');
      await probe.writeAsString('ok');
      await probe.delete();
    } catch (_) {
      if (context.mounted) {
        _error(
          context,
          "Нет прав на запись в папку программы:\n${installDir.path}\n"
          "Перенесите программу в другую папку или обновите вручную.",
        );
      }
      return;
    }

    if (!context.mounted) return;
    final progress = ValueNotifier<double>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text("Загрузка обновления"),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: value),
                const SizedBox(height: 8),
                Text("${(value * 100).round()}%"),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final workDir = Directory(
        '${Directory.systemTemp.path}\\mone_task_update_$build',
      );
      if (await workDir.exists()) await workDir.delete(recursive: true);
      await workDir.create(recursive: true);

      final zipPath = '${workDir.path}\\$assetName';
      await Dio().download(
        zipUrl,
        zipPath,
        onReceiveProgress: (received, total) {
          if (total > 0) progress.value = received / total;
        },
      );

      final filesDir = Directory('${workDir.path}\\files');
      await extractFileToDisk(zipPath, filesDir.path);

      // Zip ichida exe turgan papka (ildizda yoki bitta ichki papkada)
      final exe = await filesDir
          .list(recursive: true)
          .where((e) => e is File && e.path.toLowerCase().endsWith(_exeName))
          .cast<File>()
          .first;
      final sourceDir = exe.parent.path;

      // Ilova yopilgach fayllarni almashtirib, qayta ochadigan skript
      final script = File('${workDir.path}\\update.bat');
      await script.writeAsString(
        [
          '@echo off',
          'chcp 65001 >nul',
          ':wait',
          'tasklist /FI "PID eq $pid" 2>nul | find "$pid" >nul',
          'if not errorlevel 1 (timeout /t 1 /nobreak >nul & goto wait)',
          'robocopy "$sourceDir" "${installDir.path}" /E /R:10 /W:1 '
              '/NFL /NDL /NJH /NJS >nul',
          'start "" "${installDir.path}\\$_exeName"',
        ].join('\r\n'),
        encoding: utf8,
      );

      await Process.start('cmd.exe', [
        '/c',
        script.path,
      ], mode: ProcessStartMode.detached);
      exit(0);
    } catch (e) {
      debugPrint('Windows yangilanishi o\'rnatilmadi: $e');
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _error(context, "Не удалось обновить. Попробуйте позже.");
      }
    } finally {
      progress.dispose();
    }
  }

  static void _error(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Обновление"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }
}
