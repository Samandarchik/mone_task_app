import 'package:dio/dio.dart';
import 'package:mone_task_app/admin/model/add_admin_task.dart';
import 'package:mone_task_app/admin/model/admin_task_model.dart';
import 'package:mone_task_app/admin/model/all_task_model.dart';
import 'package:mone_task_app/admin/model/edit_task_ui_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
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

  Future<bool> addTask(AddAdminTaskModel task) async {
    try {
      final response = await _dio.post(
        AppUrls.tasks, // 🔥 shu yerga sizning POST URL’ingiz tushadi
        data: task.toJson(),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  // Edit task
  Future<bool> updateTaskStatus(EditTaskUiModel task) async {
    try {
      final response = await _dio.put(
        "${AppUrls.tasks}/${task.taskId}",
        data: task.toJson(),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<List<TemplateTaskModel>> fetchTemplates() async {
    try {
      final response = await _dio.get(AppUrls.tasksAll);

      if (response.data == null) {
        throw Exception("Task ma'lumotlari mavjud emas");
      }

      final data = response.data["data"];

      if (data is! List) {
        throw Exception("Server noto‘g‘ri format qaytardi");
      }

      return data.map((e) => TemplateTaskModel.fromJson(e)).toList();
    } catch (e) {
      rethrow; // UI ushlashi uchun
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

  Future<bool> updateTaskReorder(int old, int newIndex) async {
    try {
      final response = await _dio.put("${AppUrls.reorder}/$old/$newIndex");

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> addFilial(String filial) async {
    try {
      final response = await _dio.post(AppUrls.filial, data: {"name": filial});
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteFilial(int filial) async {
    try {
      final response = await _dio.delete("${AppUrls.filial}/$filial");
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateFilial(int filial, String name) async {
    try {
      final response = await _dio.put(
        "${AppUrls.filial}/$filial",
        data: {"name": name},
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  Future<List<CategoryModel>> fetchCategoriesList() async {
    try {
      final response = await _dio.get(AppUrls.categories); // category URL
      return (response.data['data'] as List)
          .map((e) => CategoryModel.fromJson(e))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> addCategory(String name) async {
    try {
      final response = await _dio.post(
        AppUrls.categories,
        data: {"name": name},
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteCategory(int id) async {
    try {
      final response = await _dio.delete("${AppUrls.categories}/$id");
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // --- Category API ---
  Future<List<CategoryModel>> loadCategories() async {
    try {
      final response = await _dio.get(AppUrls.categories);
      if (response.data == null) {
        return [];
      }
      return (response.data['data'] as List)
          .map((e) => CategoryModel.fromJson(e))
          .toList();
    } catch (e) {
      return [];
    }
  }
}
