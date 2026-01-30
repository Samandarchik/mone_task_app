// lib/admin/service/user_service.dart
import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/worker/model/user_model.dart';

class UserService {
  final Dio _dio = sl<Dio>();

  // Barcha userlarni olish
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

  // Userni yangilash
  Future<bool> updateUser({
    required int userId,
    required String username,
    required String role,
    List<int>? filialIds,
    List<String>? categories,
  }) async {
    try {
      final Map<String, dynamic> data = {'username': username, 'role': role};

      if (filialIds != null && filialIds.isNotEmpty) {
        data['filialIds'] = filialIds;
      }

      if (categories != null && categories.isNotEmpty) {
        data['categories'] = categories;
      }

      final response = await _dio.put('${AppUrls.users}/$userId', data: data);

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Userni o'chirish
  Future<bool> deleteUser(int userId) async {
    try {
      final response = await _dio.delete('${AppUrls.users}/$userId');

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  // lib/admin/service/user_service.dart ga qo'shing

  // User qo'shish
  Future<bool> createUser({
    required String username,
    required String login,
    required String password,
    required String role,
    List<int>? filialIds,
    List<String>? categories,
    String? notificationId,
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

      if (categories != null && categories.isNotEmpty) {
        data['categories'] = categories;
      }

      if (notificationId != null && notificationId.isNotEmpty) {
        data['notificationId'] = notificationId;
      }

      final response = await _dio.post(AppUrls.register, data: data);

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('User create error: $e');
      return false;
    }
  }
}
