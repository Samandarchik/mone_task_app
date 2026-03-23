import 'dart:io';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/worker/model/response_task_model.dart';
import 'package:mone_task_app/worker/model/task_worker_model.dart';

class TaskWorkerService {
  final Dio _dio = sl<Dio>();

  /// [date] berilmasa bugungi kun ishlatiladi
  Future<List<TaskWorkerModel>> fetchTasks({DateTime? date}) async {
    try {
      final String dateStr = DateFormat(
        'yyyy-MM-dd',
      ).format(date ?? DateTime.now());
      final response = await _dio.get(
        AppUrls.tasks,
        queryParameters: {'date': dateStr},
        // queryParameters: {'date': "2026-03-05"},
      );

      if (response.data == null) {
        throw Exception("Task ma'lumotlari mavjud emas");
      }

      final data = response.data["data"];

      if (data is! List) {
        throw Exception("Server noto'g'ri format qaytardi");
      }

      return data.map((e) => TaskWorkerModel.fromJson(e)).toList();
    } catch (e) {
      rethrow;
    }
  }

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
      return response.statusCode == 200;
    } catch (e) {
      rethrow;
    }
  }

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

      return response.statusCode == 200;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> completeTaskWithSegments({
    required int taskId,
    required List<XFile> segments,
  }) async {
    try {
      if (segments.isEmpty) throw Exception('Segmentlar mavjud emas');

      Map<String, dynamic> formDataMap = {'segment_count': segments.length};

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

      return response.statusCode == 200;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> pushAudio(int id, File filesi, DateTime date) async {
    try {
      final dateStr =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final response = await _dio.post(
        "${AppUrls.tasks}/$id/voice-comment/$dateStr",
        data: FormData.fromMap({
          "audio": await MultipartFile.fromFile(filesi.path),
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> deleteAudio(int taskId, DateTime date, int audioIndex) async {
    try {
      final dateStr =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final response = await _dio.delete(
        "${AppUrls.tasks}/$taskId/voice-comment/$dateStr/$audioIndex",
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
