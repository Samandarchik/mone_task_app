import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Windows uchun to'liq avtomatik yangilanish xizmati.
///
/// Manba — GitHub Releases (public repo, autentifikatsiya kerak emas):
///   `https://github.com/{repo}/releases/latest`
/// `build_windows.bat` (yoki GitHub Actions'dagi release.yml) zip'ni
/// `publish_release.ps1` orqali shu repoga release qilib qo'yadi
/// (tag = pubspec versiyasi, masalan v0.3.9).
///
/// Oqim: yangi versiya topilsa yopib bo'lmaydigan dialog chiqadi va DARHOL
/// o'zi yuklab boshlaydi -> zip %TEMP% ga tushadi -> ilova O'ZI (Dart'da)
/// zip'ni o'z papkasi ustiga ochadi. Windows'da ishlab turgan exe/dll'ni
/// o'chirib bo'lmaydi, lekin RENAME qilish mumkin — qulflangan fayllar
/// `.old_upd` nomiga ko'chirilib o'rniga yangisi yoziladi. So'ng yangi exe
/// ishga tushiriladi va eski jarayon yopiladi; `.old_upd` fayllar keyingi
/// ochilishda tozalanadi.
class WindowsUpdateService {
  /// Faqat zip'lar turadigan public releases repo.
  static const String _repo = 'Samandarchik/mone_task_app_releases';

  /// main.dart dagi navigatorKey (dialog shu orqali ochiladi)
  static GlobalKey<NavigatorState>? navigatorKey;

  static bool _dialogShowing = false;
  static bool _installing = false;

  // Bir vaqtda faqat BITTA tekshiruv yurishi uchun.
  static Future<bool>? _inflight;

  static Timer? _periodicTimer;

  /// Ochiq turgan ilova yangi versiyani o'tkazib yubormasligi uchun davriy
  /// tekshiruv. Kassa kompyuterlarida dastur kun bo'yi yopilmaydi — faqat
  /// ochilishdagi tekshiruv bilan yangilanish keyingi restart'gacha yetib
  /// bormasdi. GitHub'ga so'rov redirect orqali (limitsiz), shuning uchun
  /// har 30 daqiqada tekshirish bemalol.
  static void startPeriodicChecks() {
    if (!Platform.isWindows || !kReleaseMode) return;
    _periodicTimer ??= Timer.periodic(
      const Duration(minutes: 30),
      (_) => checkForUpdate(),
    );
  }

  /// Yangi versiya bormi tekshiradi; bo'lsa avto-yangilash dialogini ochib
  /// `true` qaytaradi (chaqiruvchi navigatsiyani to'xtatishi kerak).
  /// Xatolik yoki yangilanish yo'q bo'lsa `false` — ilova odatdagidek ochiladi.
  /// Parallel chaqiruvlar bitta umumiy tekshiruvni kutadi.
  static Future<bool> checkForUpdate() {
    return _inflight ??= _checkForUpdate().whenComplete(() => _inflight = null);
  }

  static Future<bool> _checkForUpdate() async {
    if (!Platform.isWindows) return false;
    // flutter run / debug'da o'zini yangilashga urinmasin.
    if (!kReleaseMode) return false;
    cleanupLeftovers();
    try {
      final release = await _fetchLatestRelease();
      if (release == null) return false;

      final packageInfo = await PackageInfo.fromPlatform();
      // MUHIM: Windows'da PackageInfo.version "0.5.7+57" ko'rinishida
      // (build raqami bilan) keladi. '+build' qismini olib tashlamasak
      // "7+57" soni 0 deb o'qilib, ilova HAR ochilishda o'zini qayta
      // yuklab o'rnatadigan cheksiz sikl bo'ladi.
      final current = packageInfo.version.trim().split('+').first;

      if (!isNewerVersion(release.version, current)) return false;
      if (_dialogShowing) return true;

      final context = navigatorKey?.currentContext;
      if (context == null || !context.mounted) return true;

      _dialogShowing = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _AutoUpdateDialog(release: release, currentVersion: current),
      ).whenComplete(() => _dialogShowing = false);
      return true;
    } catch (e) {
      debugPrint('❌ Windows yangilanish tekshiruvida xato: $e');
      return false;
    }
  }

  /// GitHub'dan eng so'nggi release versiyasini oladi.
  ///
  /// ATAYIN api.github.com ishlatilmaydi: API autentifikatsiyasiz soatiga
  /// 60 so'rov / IP bilan cheklangan — bitta ofisdagi barcha kassalar bir IP
  /// orqali chiqqanda limit tez tugab, yangilanish tekshiruvi ishlamay
  /// qolardi. O'rniga `github.com/<repo>/releases/latest` ning 302 redirect
  /// manzilidan (…/releases/tag/v0.3.9) versiya o'qiladi — bunda limit yo'q.
  /// Zip manzili esa deterministik: build_windows.bat doim
  /// `mone_task_app_v<versiya>_windows.zip` nomi bilan chiqaradi.
  static Future<_ReleaseInfo?> _fetchLatestRelease() async {
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
    final match = RegExp(
      r'/releases/tag/v?([0-9][0-9.]*)',
    ).firstMatch(location);
    if (match == null) {
      debugPrint(
        '⚠️ GitHub latest redirect topilmadi (status ${response.statusCode})',
      );
      return null;
    }
    final version = match.group(1)!.split('+').first;

    return _ReleaseInfo(
      version: version,
      zipUrl:
          'https://github.com/$_repo/releases/download/'
          'v$version/mone_task_app_v${version}_windows.zip',
      sizeBytes: 0,
    );
  }

  /// `latest > current` bo'lsa true. Nuqta bilan ajratilgan sonlar sifatida.
  static bool isNewerVersion(String latest, String current) {
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final max = l.length > c.length ? l.length : c.length;
    for (int i = 0; i < max; i++) {
      final lp = i < l.length ? l[i] : 0;
      final cp = i < c.length ? c[i] : 0;
      if (lp > cp) return true;
      if (lp < cp) return false;
    }
    return false;
  }

  /// Yuklab olingan zip'ni ilova papkasi ustiga ochadi va ilovani qayta
  /// ishga tushiradi — hammasi shu jarayonning o'zida, tashqi skriptsiz.
  ///
  /// Windows'da ishlab turgan exe/dll fayllarning USTIGA yozib bo'lmaydi,
  /// lekin ularni RENAME qilish mumkin. Shundan foydalanamiz: qulflangan
  /// fayl `.old_upd` qo'shimchasi bilan qayta nomlanadi, o'rniga yangisi
  /// yoziladi. Keyin yangi exe ishga tushirilib bu jarayon yopiladi.
  /// `.old_upd` qoldiqlarini keyingi ochilishda [cleanupLeftovers] o'chiradi.
  static Future<void> installAndRestart(String zipPath) async {
    // Qo'shimcha himoya: qanday bo'lmasin ikki marta chaqirilsa ham
    // o'rnatish faqat bir marta yuradi.
    if (_installing) return;
    _installing = true;
    try {
      await _doInstallAndRestart(zipPath);
    } catch (_) {
      // Xato — dialog «Повторить» ko'rsatadi, keyingi urinish yursin.
      _installing = false;
      rethrow;
    }
  }

  static Future<void> _doInstallAndRestart(String zipPath) async {
    final exePath = Platform.resolvedExecutable;
    final appDir = File(exePath).parent.path;
    final sep = Platform.pathSeparator;

    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final entry in archive) {
      // Compress-Archive zip'larida yo'llar '\' bilan bo'lishi mumkin.
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
        // Fayl qulflangan (ishlab turgan exe/dll) — eskisini chetga
        // rename qilib o'rniga yangisini yozamiz. Rename ham xato bersa
        // (masalan Program Files'ga ruxsat yo'q) — tashqaridagi catch
        // dialogda xabar ko'rsatadi.
        // `.old_upd` band bo'lishi mumkin: ilovaning ikkinchi ochiq oynasi hali
        // o'sha eski fayldan ishlab turibdi (o'chirib ham, ustiga rename qilib
        // ham bo'lmaydi). Shunda bo'sh nom topiladi: `.old_upd1`, `.old_upd2`...
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

    // Zip endi kerak emas.
    try {
      await File(zipPath).delete();
    } catch (_) {}

    // Yangi exe'ni ishga tushirib, eski jarayonni yopamiz.
    await Process.start(
      exePath,
      const [],
      workingDirectory: appDir,
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  /// Oldingi yangilanishdan qolgan `.old_upd` fayllarni o'chiradi.
  /// Ochilishda chaqiriladi; hali qulflangan bo'lsa — jim o'tkazib
  /// yuboriladi, keyingi safar o'chadi.
  static void cleanupLeftovers() {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      for (final entity in appDir.listSync(recursive: true)) {
        if (entity is File && RegExp(r'\.old_upd\d*$').hasMatch(entity.path)) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    try {
      final temp = Directory.systemTemp;
      for (final entity in temp.listSync()) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('mone_task_app_update')) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

class _ReleaseInfo {
  const _ReleaseInfo({
    required this.version,
    required this.zipUrl,
    required this.sizeBytes,
  });

  final String version;
  final String zipUrl;
  final int sizeBytes;
}

/// Yopib bo'lmaydigan avto-yangilash dialogi: ochilishi bilan o'zi yuklab
/// boshlaydi, progress ko'rsatadi, tugagach o'zi o'rnatib qayta ishga
/// tushiradi. Xato bo'lsa «Повторить» tugmasi chiqadi.
class _AutoUpdateDialog extends StatefulWidget {
  const _AutoUpdateDialog({
    required this.release,
    required this.currentVersion,
  });

  final _ReleaseInfo release;
  final String currentVersion;

  @override
  State<_AutoUpdateDialog> createState() => _AutoUpdateDialogState();
}

class _AutoUpdateDialogState extends State<_AutoUpdateDialog> {
  double _progress = 0; // 0..1
  bool _installing = false;
  String? _error;
  CancelToken? _cancelToken;
  // Xatodan keyin avtomatik qayta urinish (masalan release zip'i hali
  // yuklanib ulgurmagan yoki internet bir zum uzilgan bo'lsa) — kassa
  // kompyuterida hech kim «Повторить»ni bosmasligi mumkin.
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
        '${Directory.systemTemp.path}${Platform.pathSeparator}mone_task_app_update_v${widget.release.version}.zip';

    var downloaded = false;
    try {
      _cancelToken = CancelToken();
      await Dio().download(
        widget.release.zipUrl,
        zipPath,
        cancelToken: _cancelToken,
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          headers: {'Accept': 'application/octet-stream'},
        ),
        onReceiveProgress: (received, total) {
          final t = total > 0 ? total : widget.release.sizeBytes;
          if (t > 0 && mounted) {
            setState(() => _progress = received / t);
          }
        },
      );

      downloaded = true;
      if (!mounted) return;
      setState(() => _installing = true);
      // Progress UI ko'rinishi uchun kichik pauza, so'ng o'rnatish + restart.
      await Future.delayed(const Duration(milliseconds: 600));
      await WindowsUpdateService.installAndRestart(zipPath);
    } catch (e) {
      debugPrint('❌ Yangilanishda xato (yuklandi: $downloaded): $e');
      if (!mounted) return;
      setState(() {
        _installing = false;
        // Yuklab olish va o'rnatish xatosi alohida: o'rnatish odatda fayllar
        // band bo'lgani uchun yiqiladi (ilovaning ikkinchi oynasi ochiq).
        _error = downloaded
            ? 'Обновление загружено, но не установилось.\n'
                  'Закройте другие окна программы.\n'
                  'Через 30 секунд попробуем снова.'
            : 'Не удалось загрузить обновление.\nПроверьте интернет.\n'
                  'Через 30 секунд попробуем снова.';
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
          'Обновление программы',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Текущая версия: ${widget.currentVersion}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            Text(
              'Новая версия: ${widget.release.version}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ] else if (_installing) ...[
              const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Установка... программа перезапустится'),
                ],
              ),
            ] else ...[
              Text('Загрузка... $percent%'),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            ],
          ],
        ),
        actions: [
          if (_error != null)
            TextButton(
              onPressed: _startDownload,
              child: const Text('Повторить'),
            ),
        ],
      ),
    );
  }
}
