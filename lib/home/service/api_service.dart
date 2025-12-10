// services/api_service.dart
import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/model/login_model.dart';

class ApiService {
  Dio dio = sl<Dio>();
  Future<Map<String, dynamic>> login(LoginModel loginModel) async {
    try {
      final response = await dio.post(
        AppUrls.login,
        data: {
          'username': loginModel.username,
          'password': loginModel.password,
        },
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        return {
          'success': false,
          'message': 'Server xatosi: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Internetga ulanishda xato: $e'};
    }
  }
}
