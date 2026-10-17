import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';

/// Foydalanuvchining shaxsiy pin va vazifalar tartibi (backendda saqlanadi).
class TaskPrefsService {
  final Dio _dio = sl<Dio>();

  Future<bool> setPinned(int templateId, bool pinned) async {
    try {
      final response = await _dio.put(
        "${AppUrls.baseUrl}/api/task-prefs/pin/$templateId",
        data: {"pinned": pinned},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// [templateIds] — yangi tartibdagi shablon ID lari
  Future<bool> saveOrder(List<int> templateIds) async {
    try {
      final response = await _dio.put(
        "${AppUrls.baseUrl}/api/task-prefs/order",
        data: {"order": templateIds},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
