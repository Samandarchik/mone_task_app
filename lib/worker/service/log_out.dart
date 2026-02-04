import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';

class LogOutService {
  Dio dio = sl<Dio>();
  Future<bool> logOut() async {
    try {
      final response = await dio.post(AppUrls.logOut);
      if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
