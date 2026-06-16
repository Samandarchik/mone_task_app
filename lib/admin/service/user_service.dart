import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/worker/model/user_model.dart';

class UserService {
  final Dio _dio = sl<Dio>();

  Future<List<UserModel>> fetchUsers() async {
    try {
      final response = await _dio.get(AppUrls.users);
      if (response.statusCode == 200) {
        final usersResponse = UsersResponse.fromJson(response.data);
        return usersResponse.data;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> updateUser({
    required int userId,
    required String username,
    required String role,
    String? password,
    List<int>? filialIds,
    String? phoneNumber,
    String? profileJson,
  }) async {
    try {
      final Map<String, dynamic> data = {'username': username, 'role': role};
      if (password != null && password.isNotEmpty) {
        data['password'] = password;
      }
      if (filialIds != null && filialIds.isNotEmpty) {
        data['filialIds'] = filialIds;
      }
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        data['phoneNumber'] = phoneNumber;
      }
      if (profileJson != null && profileJson.isNotEmpty) {
        data['profileJson'] = profileJson;
      }
      final response = await _dio.put('${AppUrls.users}/$userId', data: data);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteUser(int userId) async {
    try {
      final response = await _dio.delete('${AppUrls.users}/$userId');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Bitta foydalanuvchiga login ma'lumotlarini (ism + login + parol + ilova
  /// linklari) Telegram orqali yuboradi. Xatoda server xabari bilan exception.
  Future<void> sendCredentials(int userId) async {
    try {
      await _dio.post('${AppUrls.users}/$userId/send-credentials');
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = (data is Map && data['error'] != null)
          ? data['error'].toString()
          : 'Не удалось отправить';
      throw Exception(msg);
    }
  }

  /// super_admin'dan boshqa barcha foydalanuvchilarga login ma'lumotlarini
  /// (ism + login + parol + ilova iOS/Android linklari) bittada Telegram orqali
  /// yuboradi. Server javobi: {sent, skipped: [...], failed: [...]}.
  Future<Map<String, dynamic>> sendAllCredentials() async {
    final response = await _dio.post('${AppUrls.users}/send-all-credentials');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    return <String, dynamic>{};
  }

  Future<bool> createUser({
    required String username,
    required String login,
    required String password,
    required String role,
    List<int>? filialIds,
    String? notificationId,
    String? phoneNumber,
    String? profileJson,
  }) async {
    try {
      final Map<String, dynamic> data = {
        'username': username,
        'login': login,
        'password': password,
        'role': role,
      };
      if (filialIds != null && filialIds.isNotEmpty) {
        data['filialIds'] = filialIds;
      }
      if (notificationId != null && notificationId.isNotEmpty) {
        data['notificationId'] = notificationId;
      }
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        data['phoneNumber'] = phoneNumber;
      }
      if (profileJson != null && profileJson.isNotEmpty) {
        data['profileJson'] = profileJson;
      }
      final response = await _dio.post(AppUrls.register, data: data);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }
}
