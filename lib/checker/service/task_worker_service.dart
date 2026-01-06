import 'package:dio/dio.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/admin/model/add_admin_task.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/worker/model/response_task_model.dart';

class AdminTaskService {
  final Dio _dio = sl<Dio>();

  Future<List<CheckerCheckTaskModel>> fetchTasks() async {
    try {
      final response = await _dio.get(AppUrls.taskProof);

      if (response.data == null) {
        throw Exception("Task ma'lumotlari mavjud emas");
      }

      final data = response.data;

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
        "task_id": request.id,
        if (request.text != null) "text": request.text,
        if (request.file != null)
          "file": await MultipartFile.fromFile(
            request.file!.path,
            filename: request.file!.name,
          ),
      });

      final response = await _dio.post(AppUrls.completeTask, data: formData);
      return response.statusCode == 200;
    } catch (e) {
      rethrow; // UI ushlashi uchun
    }
  }

  Future<bool> deleteTask(int taskId) async {
    try {
      final response = await _dio.delete("${AppUrls.deleteTask}$taskId");
      return response.statusCode == 200;
    } catch (e) {
      rethrow; // UI ushlashi uchun
    }
  }

  Future<bool> createTask(AddAdminTaskModel task) async {
    try {
      final response = await _dio.post(
        AppUrls.addTask, // 🔥 shu yerga sizning POST URL’ingiz tushadi
        data: {
          "description": task.description,
          "task_type": task.taskType,
          "role": task.role,
          "filials_id": task.filialsId,
        },
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> addTask(AddAdminTaskModel task) async {
    try {
      final response = await _dio.post(
        AppUrls.addTask, // 🔥 shu yerga sizning POST URL’ingiz tushadi
        data: {
          "description": task.description,
          "task_type": task.taskType,
          "role": task.role,
          "filials_id": task.filialsId,
        },
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateTaskStatus(int taskId) async {
    try {
      final response = await _dio.post("${AppUrls.taskProof}$taskId/approve");
      print(response.statusCode);
    } catch (e) {}
  }
}
