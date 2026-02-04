import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';

class LogOutService {
  Dio dio = sl<Dio>();
  Future<void> logOut() async {
    try {
      await dio.post(AppUrls.logOut);
    } catch (e) {}
  }
}
