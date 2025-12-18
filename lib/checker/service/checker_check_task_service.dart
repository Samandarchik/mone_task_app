import 'package:dio/dio.dart';
import 'package:mone_task_app/admin%20copy/model/checker_check_task_model.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';

class CheckerCheckTaskService {
  Dio dio = sl<Dio>();
  Future<List<CheckerCheckTaskModel>> fetchTasks() async {
    try {
      final response = await dio.get(AppUrls.taskProof);

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
}
