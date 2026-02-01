import 'package:dio/dio.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/worker/model/response_task_model.dart';

class AdminTaskService {
  final Dio _dio = sl<Dio>();

  Future<List<CheckerCheckTaskModel>> fetchTasks(DateTime selectedDate) async {
    try {
      final response = await _dio.get(
        "${AppUrls.tasks}?date=${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}",
      );

      if (response.data == null) {
        throw Exception("Task ma'lumotlari mavjud emas");
      }

      final data = response.data['data'];

      if (data is! List) {
        throw Exception("Server noto‘g‘ri format qaytardi");
      }

      return data.map((e) => CheckerCheckTaskModel.fromJson(e)).toList();
    } catch (e) {
      rethrow; // UI ushlashi uchun
    }
  }

  Future<bool> completeTask(RequestTaskModel request) async {
    try {
      final formData = FormData.fromMap({
        "video": await MultipartFile.fromFile(
          request.file!.path,
          filename: request.file!.name,
        ),
      });

      final response = await _dio.post(
        "${AppUrls.tasks}/${request.id}/submit",
        data: formData,
      );
      return response.statusCode == 200;
    } catch (e) {
      rethrow; // UI ushlashi uchun
    }
  }

  Future<bool> deleteTask(int taskId) async {
    try {
      final response = await _dio.delete("${AppUrls.deleteTask}/$taskId");
      return response.statusCode == 200;
    } catch (e) {
      rethrow; // UI ushlashi uchun
    }
  }

  Future<bool> updateTaskStatus(int taskId, int status, DateTime date) async {
    try {
      final response = await _dio.post(
        "${AppUrls.tasks}/$taskId/check/${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}",
        data: {"status": status},
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<List<FilialModel>> fetchCategories() async {
    try {
      final response = await _dio.get(AppUrls.filial);
      return (response.data['data'] as List)
          .map((e) => FilialModel.fromJson(e))
          .toList();
    } catch (e) {
      rethrow; // UI ushlashi uchun
    }
  }
}
