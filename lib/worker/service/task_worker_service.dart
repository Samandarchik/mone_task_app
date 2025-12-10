import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/worker/model/response_task_model.dart';
import 'package:mone_task_app/worker/model/task_worker_model.dart';

class TaskWorkerService {
  final Dio _dio = sl<Dio>();

  Future<List<TaskWorkerModel>> fetchTasks() async {
    try {
      final response = await _dio.get(AppUrls.workerTasks);

      if (response.data == null) {
        throw Exception("Task ma'lumotlari mavjud emas");
      }

      final data = response.data;

      if (data is! List) {
        throw Exception("Server noto‘g‘ri format qaytardi");
      }

      return data.map((e) => TaskWorkerModel.fromJson(e)).toList();
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
      print("Response status: ${response.statusCode}");
      return response.statusCode == 200;
    } catch (e) {
      rethrow; // UI ushlashi uchun
    }
  }
}
