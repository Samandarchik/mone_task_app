import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Windows ilovasini to'liq avtomatik yangilash (HR ilovasidagidek).
///
/// Manba — shu repo'ning GitHub Releases'i. Versiya ko'tarilib `main` ga
/// push qilinganda `.github/workflows/release.yml` Windows build'ni
/// `windows-<versiya>-<build>` tegli release'ga [assetName] qilib qo'yadi.
///
/// Oqim: yangi versiya topilsa yopib bo'lmaydigan oyna chiqadi va DARHOL
/// o'zi yuklab boshlaydi -> zip %TEMP% ga tushadi -> ilova O'ZI zip'ni o'z
/// papkasi ustiga ochadi. Windows'da ishlab turgan exe/dll'ni o'chirib
/// bo'lmaydi, lekin RENAME qilish mumkin — band fayllar `.old_upd` nomiga
/// ko'chirilib o'rniga yangisi yoziladi. So'ng yangi exe ishga tushiriladi va
/// eski jarayon yopiladi; `.old_upd` fayllar keyingi ochilishda tozalanadi.
class WindowsUpdater {
  static const _repo = 'Samandarchik/mone_task_app';
  static const tagPrefix = 'windows-';
  static const assetName = 'mone_task_app_windows.zip';

  static GlobalKey<NavigatorState>? _navigatorKey;
  static Timer? _periodicTimer;
  static bool _dialogShowing = false;
  static bool _installing = false;
  static Future<void>? _inflight;

  /// Ochilishda va har 30 daqiqada tekshiradi — kompyuterlarda dastur kun
  /// bo'yi yopilmaydi. So'rov github.com redirect orqali (limitsiz).
  static void start(GlobalKey<NavigatorState> navigatorKey) {
    // flutter run / debug'da o'zini yangilashga urinmasin
    if (!Platform.isWindows || !kReleaseMode) return;
    if (_periodicTimer != null) return;
    _navigatorKey = navigatorKey;
    _cleanupLeftovers();
    // Ilova to'liq ochilib olsin
    Future.delayed(const Duration(seconds: 5), check);
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => check(),
    );
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

  /// Bir vaqtda faqat bitta tekshiruv yuradi
  static Future<void> check() =>
      _inflight ??= _check().whenComplete(() => _inflight = null);

  static Future<void> _check() async {
    if (_dialogShowing || _installing) return;
    try {
      final tag = await _latestTag();
      if (tag == null) return;
      final latestBuild = buildFromTag(tag);
      if (latestBuild == null) return;

      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      if (latestBuild <= currentBuild) return;

      final context = _navigatorKey?.currentContext;
      if (context == null || !context.mounted || _dialogShowing) return;

      _dialogShowing = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AutoUpdateDialog(
          currentVersion: info.version.split('+').first,
          newVersion: versionFromTag(tag),
          zipUrl: 'https://github.com/$_repo/releases/download/$tag/$assetName',
        ),
      ).whenComplete(() => _dialogShowing = false);
    } catch (e) {
      debugPrint('Windows yangilanishini tekshirib bo\'lmadi: $e');
    }
  }

  /// Eng so'nggi release tegi.
  ///
  /// ATAYIN api.github.com ishlatilmaydi: autentifikatsiyasiz soatiga 60
  /// so'rov / IP — bitta ofisdagi barcha kompyuterlar bir IP orqali chiqsa
  /// limit tez tugaydi. `github.com/<repo>/releases/latest` ning redirect
  /// manzilidan (…/releases/tag/windows-0.3.9-309) teg o'qiladi — limitsiz.
  static Future<String?> _latestTag() async {
    final response =
        await Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
          ),
        ).get(
          'https://github.com/$_repo/releases/latest',
          options: Options(followRedirects: false, validateStatus: (_) => true),
        );
    final location = response.headers.value('location') ?? '';
    return RegExp(r'/releases/tag/([^/?#]+)').firstMatch(location)?.group(1);
  }

  /// Zip'ni ilova papkasi ustiga ochadi va ilovani qayta ishga tushiradi —
  /// hammasi shu jarayonning o'zida, tashqi skriptsiz.
  static Future<void> installAndRestart(String zipPath) async {
    if (_installing) return;
    _installing = true;
    try {
      await _doInstallAndRestart(zipPath);
    } catch (_) {
      // Xato — oyna «Повторить» ko'rsatadi, keyingi urinish yursin
      _installing = false;
      rethrow;
    }
  }

  static Future<void> _doInstallAndRestart(String zipPath) async {
    final exePath = Platform.resolvedExecutable;
    final appDir = File(exePath).parent.path;
    final sep = Platform.pathSeparator;

    final archive = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    for (final entry in archive) {
      // Compress-Archive zip'larida yo'llar '\' bilan bo'lishi mumkin
      final rel = entry.name.replaceAll('\\', '/');
      if (rel.isEmpty || rel.contains('..')) continue;

      final targetPath = '$appDir$sep${rel.replaceAll('/', sep)}';
      if (!entry.isFile) {
        Directory(targetPath).createSync(recursive: true);
        continue;
      }
      final target = File(targetPath);
      target.parent.createSync(recursive: true);
      final data = entry.readBytes();
      if (data == null) continue;

      try {
        target.writeAsBytesSync(data, flush: true);
      } on FileSystemException {
        // Fayl band (ishlab turgan exe/dll) — eskisini chetga rename qilib
        // o'rniga yangisini yozamiz. `.old_upd` ham band bo'lishi mumkin
        // (ilovaning ikkinchi oynasi ochiq) — bo'sh nom topiladi.
        var old = File('$targetPath.old_upd');
        try {
          if (old.existsSync()) old.deleteSync();
        } catch (_) {}
        for (var n = 1; old.existsSync() && n < 50; n++) {
          old = File('$targetPath.old_upd$n');
          try {
            if (old.existsSync()) old.deleteSync();
          } catch (_) {}
        }
        target.renameSync(old.path);
        target.writeAsBytesSync(data, flush: true);
      }
    }

    try {
      await File(zipPath).delete();
    } catch (_) {}

    // Yangi exe'ni ishga tushirib, eski jarayonni yopamiz
    await Process.start(
      exePath,
      const [],
      workingDirectory: appDir,
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  /// Oldingi yangilanishdan qolgan `.old_upd` fayllar va zip'lar
  static void _cleanupLeftovers() {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      for (final e in appDir.listSync(recursive: true)) {
        if (e is File && RegExp(r'\.old_upd\d*$').hasMatch(e.path)) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    try {
      for (final e in Directory.systemTemp.listSync()) {
        final name = e.path.split(Platform.pathSeparator).last;
        if (name.startsWith('mone_task_app_update')) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

/// Yopib bo'lmaydigan avto-yangilash oynasi: ochilishi bilan o'zi yuklab
/// boshlaydi, tugagach o'zi o'rnatib qayta ishga tushiradi. Xato bo'lsa
/// 30 soniyadan keyin o'zi qayta urinadi (kompyuterda hech kim bosmasligi
/// mumkin).
class _AutoUpdateDialog extends StatefulWidget {
  final String currentVersion;
  final String newVersion;
  final String zipUrl;

  const _AutoUpdateDialog({
    required this.currentVersion,
    required this.newVersion,
    required this.zipUrl,
  });

  @override
  State<_AutoUpdateDialog> createState() => _AutoUpdateDialogState();
}

class _AutoUpdateDialogState extends State<_AutoUpdateDialog> {
  double _progress = 0;
  bool _installing = false;
  String? _error;
  CancelToken? _cancelToken;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    _retryTimer?.cancel();
    setState(() {
      _installing = false;
      _error = null;
      _progress = 0;
    });

    final zipPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'mone_task_app_update_${widget.newVersion}.zip';
    var downloaded = false;
    try {
      _cancelToken = CancelToken();
      await Dio().download(
        widget.zipUrl,
        zipPath,
        cancelToken: _cancelToken,
        options: Options(receiveTimeout: const Duration(minutes: 10)),
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );
      downloaded = true;
      if (!mounted) return;
      setState(() => _installing = true);
      await Future.delayed(const Duration(milliseconds: 600));
      await WindowsUpdater.installAndRestart(zipPath);
    } catch (e) {
      debugPrint('Yangilanishda xato (yuklandi: $downloaded): $e');
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = downloaded
            ? "Обновление загружено, но не установилось.\n"
                  "Закройте другие окна программы.\n"
                  "Через 30 секунд попробуем снова."
            : "Не удалось загрузить обновление.\n"
                  "Проверьте интернет.\n"
                  "Через 30 секунд попробуем снова.";
      });
      _retryTimer = Timer(const Duration(seconds: 30), () {
        if (mounted && !_installing) _startDownload();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress * 100).clamp(0, 100).toStringAsFixed(0);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text(
          "Обновление программы",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Текущая версия: ${widget.currentVersion}",
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            Text(
              "Новая версия: ${widget.newVersion}",
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else if (_installing)
              const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text("Установка... программа перезапустится"),
                  ),
                ],
              )
            else ...[
              Text("Загрузка... $percent%"),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            ],
          ],
        ),
        actions: [
          if (_error != null)
            TextButton(
              onPressed: _startDownload,
              child: const Text("Повторить"),
            ),
        ],
      ),
    );
  }
}
