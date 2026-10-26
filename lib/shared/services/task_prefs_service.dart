import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';

/// WS: vazifalar tartibini shu foydalanuvchining o'zi o'zgartirgan — ro'yxat
/// allaqachon yangi tartibda, qayta yuklash shart emas.
bool isOwnOrderChange(Map<String, dynamic> event) {
  final data = event['data'];
  if (event['event'] != 'task_updated' || data is! Map) return false;
  if (data['action'] != 'order_changed') return false;
  final me = sl<TokenStorage>().getUserData()?.userId;
  return me != null && '${data['userId']}' == '$me';
}

/// Filialdagi vazifalar tartibi — hamma uchun bitta (backendda saqlanadi,
/// o'zgarsa WS orqali hammaga `order_changed` keladi).
class TaskPrefsService {
  final Dio _dio = sl<Dio>();

  /// [templateIds] — [filialId] dagi yangi tartibdagi shablon ID lari.
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
