import 'dart:io';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

Future<File> compressVideoTo500(File inputFile) async {
  final tempDir = await getTemporaryDirectory();
  final outputPath = p.join(
    tempDir.path,
    "video_500x500_${DateTime.now().millisecondsSinceEpoch}.mp4",
  );

  // FFmpeg command: resize to EXACT 500x500
  final cmd = '''
  -i "${inputFile.path}"
  -vf scale=500:500
  -vcodec libx264
  -crf 24
  -preset medium
  -acodec aac
  "$outputPath"
  ''';

  await FFmpegKit.execute(cmd);

  return File(outputPath);
}
