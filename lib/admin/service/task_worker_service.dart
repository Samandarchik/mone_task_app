import 'package:dio/dio.dart';
import 'package:mone_task_app/admin/model/add_admin_task.dart';
import 'package:mone_task_app/admin/model/admin_task_model.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';

class AdminTaskService {
  final Dio _dio = sl<Dio>();

  Future<List<AdminTaskModel>> fetchTasks() async {
    try {
      final response = await _dio.get(AppUrls.tasks);

      if (response.data == null) {
        throw Exception("Task ma'lumotlari mavjud emas");
      }

      final data = response.data["data"];

      if (data is! List) {
        throw Exception("Server noto‘g‘ri format qaytardi");
      }

      return data.map((e) => AdminTaskModel.fromJson(e)).toList();
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
        AppUrls.tasks, // 🔥 shu yerga sizning POST URL’ingiz tushadi
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
        AppUrls.tasks, // 🔥 shu yerga sizning POST URL’ingiz tushadi
        data: {
          "description": task.description,
          "task_type": task.taskType,
          "role": task.role,
          "filials_id": task.filialsId,
        },
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }
}
