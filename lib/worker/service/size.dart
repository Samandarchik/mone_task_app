import 'dart:io';
import 'package:light_compressor/light_compressor.dart';

Future<File> compressVideo(File file) async {
  final LightCompressor _compressor = LightCompressor();

  final String videoName =
      'compressed-${DateTime.now().millisecondsSinceEpoch}.mp4';

  final Result result = await _compressor.compressVideo(
    path: file.path,
    videoQuality: VideoQuality.low, // 🔥 500x500 ga eng yaqin
    isMinBitrateCheckEnabled: false,
    video: Video(videoName: videoName),
    android: AndroidConfig(isSharedStorage: false, saveAt: SaveAt.Downloads),
    ios: IOSConfig(saveInGallery: false),
  );

  if (result is OnSuccess) {
    return File(result.destinationPath);
  } else if (result is OnFailure) {
    throw Exception("Compression failed: ${result.message}");
  } else if (result is OnCancelled) {
    throw Exception("Compression cancelled");
  }

  throw Exception("Unknown compression error");
}
