import 'package:dio/dio.dart';
import 'package:mone_task_app/admin/model/add_admin_task.dart';
import 'package:mone_task_app/admin/model/admin_task_model.dart';
import 'package:mone_task_app/admin/model/all_task_model.dart';
import 'package:mone_task_app/admin/model/edit_task_ui_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/core/network/dio_settings.dart';

/// Admin template CRUD — task yaratish, tahrirlash, o'chirish, tartib.
/// Filial va Category boshqaruvi ham shu yerda.
class TemplateService {
  final Dio _dio = sl<Dio>();

  Future<List<AdminTaskModel>> fetchTasks() async {
    try {
      final response = await _dio.get(AppUrls.tasks);

      if (response.data == null) {
        throw Exception("Данные задачи отсутствуют");
      }

      final data = response.data["data"];

      if (data is! List) {
        throw Exception("Сервер вернул неверный формат");
      }

      return data.map((e) => AdminTaskModel.fromJson(e)).toList();
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
        throw Exception("Данные задачи отсутствуют");
      }

      final data = response.data["data"];

      if (data is! List) {
        throw Exception("Сервер вернул неверный формат");
      }

      return data.map((e) => TemplateTaskModel.fromJson(e)).toList();
    } catch (e) {
      rethrow; // UI ushlashi uchun
    }
  }

  Future<List<FilialModel>> fetchFilials() async {
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

  /// Filiallarning yangi tartibi — barcha ekranlarda shu tartibda chiqadi
  Future<bool> reorderFilials(List<int> filialIds) async {
    try {
      final response = await _dio.put(
        "${AppUrls.filial}/reorder",
        data: {"filialIds": filialIds},
      );
      return response.statusCode == 200;
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

  Future<bool> updateCategory(int id, String name) async {
    try {
      final response = await _dio.put(
        "${AppUrls.categories}/$id",
        data: {"name": name},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Kategoriyalarning yangi tartibi — ro'yxatlarda shu tartibda chiqadi
  Future<bool> reorderCategories(List<int> categoryIds) async {
    try {
      final response = await _dio.put(
        "${AppUrls.categories}/reorder",
        data: {"categoryIds": categoryIds},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Nomini o'zgartirish — server vazifa va xodimlardagi nomni ham yangilaydi.
  /// Xato bo'lsa — uning matni, aks holda null.
  Future<String?> renameCategory(int id, String name) async {
    try {
      await _dio.put("${AppUrls.categories}/$id", data: {"name": name});
      return null;
    } on DioException catch (e) {
      return _serverError(e) ?? 'Не удалось переименовать';
    }
  }

  /// O'chirish — ishlatilayotgan bo'lsa server rad etadi va sababini aytadi
  Future<String?> removeCategory(int id) async {
    try {
      await _dio.delete("${AppUrls.categories}/$id");
      return null;
    } on DioException catch (e) {
      return _serverError(e) ?? 'Не удалось удалить';
    }
  }

  String? _serverError(DioException e) {
    final data = e.response?.data;
    return data is Map && data['error'] is String ? data['error'] : null;
  }

  Future<bool> putStatus(int id, int status) async {
    try {
      final response = await _dio.post(
        // /api/tasks/1/check
        "${AppUrls.tasks}/$id/check",
        data: {"status": status},
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  /// Namuna video yuklash — bir xil matnli vazifaning barcha filiallardagi
  /// shablonlariga qo'yiladi. [paths] — bitta fayl yoki pauza bilan olingan
  /// bo'laklar (serverda birlashtiriladi). Muvaffaqiyatli bo'lsa video URL.
  Future<String?> uploadGuideVideo(
    int templateId,
    List<String> paths, {
    ProgressCallback? onProgress,
  }) async {
    final fields = <String, dynamic>{
      if (paths.length > 1) "segment_count": paths.length,
    };
    for (var i = 0; i < paths.length; i++) {
      fields[paths.length > 1
          ? "video_$i"
          : "video"] = await MultipartFile.fromFile(
        paths[i],
        filename: paths[i].split(RegExp(r'[/\\]')).last,
      );
    }
    final response = await _dio.post(
      "${AppUrls.baseUrl}/api/templates/$templateId/guide-video",
      data: FormData.fromMap(fields),
      options: videoUploadOptions,
      onSendProgress: onProgress,
    );
    if (response.statusCode != 200) return null;
    return response.data['guideVideoUrl'] as String?;
  }

  Future<bool> deleteGuideVideo(int templateId) async {
    try {
      final response = await _dio.delete(
        "${AppUrls.baseUrl}/api/templates/$templateId/guide-video",
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
