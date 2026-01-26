// import 'dart:io';
// import 'package:path_provider/path_provider.dart';
// import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
// import 'package:ffmpeg_kit_flutter/return_code.dart';

// class VideoMerger {
//   static Future<String> mergeVideos(List<String> videoPaths) async {
//     if (videoPaths.isEmpty) {
//       throw Exception('Video ro\'yxati bo\'sh');
//     }

//     if (videoPaths.length == 1) {
//       // Faqat bitta video bo'lsa, uni qaytarish
//       return videoPaths[0];
//     }

//     try {
//       // Vaqtinchalik fayl yaratish
//       final directory = await getTemporaryDirectory();
//       final timestamp = DateTime.now().millisecondsSinceEpoch;
//       final outputPath = '${directory.path}/merged_video_$timestamp.mp4';

//       // FFmpeg concat demuxer uchun fayl ro'yxatini yaratish
//       final fileListPath = '${directory.path}/file_list_$timestamp.txt';
//       final fileListContent = videoPaths
//           .map((path) => "file '${path.replaceAll("'", "'\\''")}'")
//           .join('\n');

//       await File(fileListPath).writeAsString(fileListContent);

//       // FFmpeg buyrug'i - concat demuxer ishlatish (qayta kodlashsiz)
//       final command =
//           '-f concat -safe 0 -i "$fileListPath" -c copy "$outputPath"';

//       // FFmpeg ni bajarish
//       final session = await FFmpegKit.execute(command);
//       final returnCode = await session.getReturnCode();

//       // Vaqtinchalik fayl ro'yxatini o'chirish
//       try {
//         await File(fileListPath).delete();
//       } catch (e) {
//         // Ignore
//       }

//       if (ReturnCode.isSuccess(returnCode)) {
//         return outputPath;
//       } else {
//         final logs = await session.getOutput();
//         throw Exception('Video birlashtirish xatosi: $logs');
//       }
//     } catch (e) {
//       throw Exception('Video birlashtirish xatosi: $e');
//     }
//   }

//   // Muqobil usul: qayta kodlash bilan birlashtirish (sekinroq, lekin ishonchli)
//   static Future<String> mergeVideosWithReencode(List<String> videoPaths) async {
//     if (videoPaths.isEmpty) {
//       throw Exception('Video ro\'yxati bo\'sh');
//     }

//     if (videoPaths.length == 1) {
//       return videoPaths[0];
//     }

//     try {
//       final directory = await getTemporaryDirectory();
//       final timestamp = DateTime.now().millisecondsSinceEpoch;
//       final outputPath = '${directory.path}/merged_video_$timestamp.mp4';

//       final fileListPath = '${directory.path}/file_list_$timestamp.txt';
//       final fileListContent = videoPaths
//           .map((path) => "file '${path.replaceAll("'", "'\\''")}'")
//           .join('\n');

//       await File(fileListPath).writeAsString(fileListContent);

//       // Qayta kodlash bilan birlashtirish
//       final command =
//           '-f concat -safe 0 -i "$fileListPath" '
//           '-c:v libx264 -preset ultrafast -crf 23 '
//           '-c:a aac -b:a 128k '
//           '"$outputPath"';

//       final session = await FFmpegKit.execute(command);
//       final returnCode = await session.getReturnCode();

//       try {
//         await File(fileListPath).delete();
//       } catch (e) {
//         // Ignore
//       }

//       if (ReturnCode.isSuccess(returnCode)) {
//         return outputPath;
//       } else {
//         final logs = await session.getOutput();
//         throw Exception('Video birlashtirish xatosi: $logs');
//       }
//     } catch (e) {
//       throw Exception('Video birlashtirish xatosi: $e');
//     }
//   }
// }
