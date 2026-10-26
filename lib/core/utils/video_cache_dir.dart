import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Keshlangan videolar papkasi.
///
/// Windowsda `Documents` ko'pincha OneDrive bilan sinxronlanadi yoki
/// «Controlled folder access» bilan himoyalangan bo'ladi — u yerga yozish
/// xato beradi. Shuning uchun Windowsda AppData (application support)
/// ishlatiladi; mobil qurilmalarda eski joy saqlanadi (kesh yo'qolmasin).
Future<Directory> getVideoCacheDir() async {
  final base = Platform.isWindows
      ? await getApplicationSupportDirectory()
      : await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}videos');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}
