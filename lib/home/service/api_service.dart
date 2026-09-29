import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/home/model/login_model.dart';

class ApiService {
  Dio dio = sl<Dio>();

  /// Natija: `{success, token, user}` yoki `{success: false, message, detail?}`.
  /// `message` — foydalanuvchiga ko'rsatiladigan qisqa o'zbekcha matn,
  /// `detail` — texnik tafsilot (kichik harfda ko'rsatish uchun).
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
          'message': tr("Serverda xatolik yuz berdi. Keyinroq urinib ko'ring."),
          'detail': 'HTTP ${response.statusCode}',
        };
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final statusCode = e.response!.statusCode;
        if (statusCode == 401 || statusCode == 409) {
          final data = e.response!.data;
          final serverMsg = data is Map ? data['error']?.toString() : null;
          return {
            'success': false,
            'message': tr("Parol noto'g'ri. Qaytadan kiriting."),
            if (serverMsg != null && serverMsg.isNotEmpty) 'detail': serverMsg,
          };
        }
        return {
          'success': false,
          'message': tr("Serverda xatolik yuz berdi. Keyinroq urinib ko'ring."),
          'detail': 'HTTP $statusCode',
        };
      }
      return {
        'success': false,
        'message': tr(
          "Internetga ulanib bo'lmadi. Aloqani tekshirib, qayta urinib ko'ring.",
        ),
        if (e.message != null) 'detail': e.message,
      };
    } catch (e) {
      return {
        'success': false,
        'message': tr("Kutilmagan xatolik yuz berdi."),
        'detail': e.toString(),
      };
    }
  }
}
