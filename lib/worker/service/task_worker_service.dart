import 'dart:io';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/worker/model/response_task_model.dart';
import 'package:mone_task_app/worker/model/task_worker_model.dart';

class TaskWorkerService {
  final Dio _dio = sl<Dio>();

  Future<List<TaskWorkerModel>> fetchTasks() async {
    try {
      final response = await _dio.get(AppUrls.tasks);

      if (response.data == null) {
        throw Exception("Task ma'lumotlari mavjud emas");
      }

      final data = response.data["data"];

      if (data is! List) {
        throw Exception("Server noto'g'ri format qaytardi");
      }

      return data.map((e) => TaskWorkerModel.fromJson(e)).toList();
    } catch (e) {
      rethrow; // UI ushlashi uchun
    }
  }

  /// Bitta video faylni yuborish (eski funksiya)
  Future<bool> completeTask(RequestTaskModel request) async {
    try {
      final compressedVideo = File(request.file!.path);

      final formData = FormData.fromMap({
        "video": await MultipartFile.fromFile(
          compressedVideo.path,
          filename: request.file!.name,
        ),
      });

      final response = await _dio.post(
        "${AppUrls.tasks}/${request.id}/submit",
        data: formData,
      );
      print(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      rethrow;
    }
  }

  /// VARIANT 1: Har bir segmentni alohida yuborish
  /// Bu variantda har bir segment alohida request sifatida yuboriladi
  Future<bool> completeTaskSegment({
    required int taskId,
    required XFile segment,
    required int segmentNumber,
    required int totalSegments,
  }) async {
    try {
      final videoFile = File(segment.path);

      final formData = FormData.fromMap({
        "video": await MultipartFile.fromFile(
          videoFile.path,
          filename: "segment_${segmentNumber}_of_$totalSegments.mp4",
        ),
        "segment_number": segmentNumber,
        "total_segments": totalSegments,
      });

      final response = await _dio.post(
        "${AppUrls.tasks}/$taskId/submit-segment",
        data: formData,
        onSendProgress: (sent, total) {
          final progress = (sent / total * 100).toStringAsFixed(0);
          print('📤 Segment $segmentNumber yuklanyapti: $progress%');
        },
      );

      print(
        '✅ Segment $segmentNumber yuklandi. Status: ${response.statusCode}',
      );
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Segment $segmentNumber yuklashda xatolik: $e');
      rethrow;
    }
  }

  /// VARIANT 2: Barcha segmentlarni bitta requestda yuborish
  /// Bu variantda barcha segmentlar bitta multipart requestda yuboriladi
  Future<bool> completeTaskWithSegments({
    required int taskId,
    required List<XFile> segments,
  }) async {
    try {
      if (segments.isEmpty) {
        throw Exception('Segmentlar mavjud emas');
      }

      Map<String, dynamic> formDataMap = {'segment_count': segments.length};

      // Barcha segmentlarni qo'shish
      for (int i = 0; i < segments.length; i++) {
        final videoFile = File(segments[i].path);
        formDataMap['video_$i'] = await MultipartFile.fromFile(
          videoFile.path,
          filename: 'segment_$i.mp4',
        );
      }

      final formData = FormData.fromMap(formDataMap);

      final response = await _dio.post(
        "${AppUrls.tasks}/$taskId/submit",
        data: formData,
        onSendProgress: (sent, total) {
          final progress = (sent / total * 100).toStringAsFixed(0);
          print('📤 Barcha segmentlar yuklanmoqda: $progress%');
        },
      );

      print('✅ Barcha segmentlar yuklandi. Status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Segmentlarni yuklashda xatolik: $e');
      rethrow;
    }
  }
}
