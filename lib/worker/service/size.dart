import 'dart:io';
import 'package:video_compress/video_compress.dart';

Future<File> compressVideo(File file) async {
  await VideoCompress.setLogLevel(0);
  await VideoCompress.deleteAllCache();

  final info = await VideoCompress.compressVideo(
    file.path,
    quality: VideoQuality.Res640x480Quality, // 👈 400 ga eng yaqin
    deleteOrigin: false,
    includeAudio: true,
  );

  return info!.file!;
}
