import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';

/// Foydalanuvchining shaxsiy vazifalar tartibi (backendda saqlanadi).
class TaskPrefsService {
  final Dio _dio = sl<Dio>();

  /// [templateIds] — [filialId] dagi yangi tartibdagi shablon ID lari.
  /// Tartib filial bo'yicha alohida saqlanadi (bitta vazifa bir nechta
  /// filialda bo'lsa, bir joyda sudrash boshqasini buzmaydi).
  Future<bool> saveOrder(int filialId, List<int> templateIds) async {
    try {
      final response = await _dio.put(
        "${AppUrls.baseUrl}/api/task-prefs/order",
        data: {"filialId": filialId, "order": templateIds},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
