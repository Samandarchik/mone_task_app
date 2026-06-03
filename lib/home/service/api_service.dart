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
        data: {'password': loginModel.password},
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        return {
          'success': false,
          'message': 'Ошибка сервера: ${response.statusCode}',
        };
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final statusCode = e.response!.statusCode;
        if (statusCode == 401 || statusCode == 409) {
          return {
            'success': false,
            'message': e.response!.data['error'] ?? 'Неверный пароль',
          };
        }
        return {'success': false, 'message': 'Ошибка сервера: $statusCode'};
      }
      return {
        'success': false,
        'message': 'Ошибка подключения к интернету: ${e.message}',
      };
    } catch (e) {
      return {'success': false, 'message': 'Непредвиденная ошибка: $e'};
    }
  }
}
