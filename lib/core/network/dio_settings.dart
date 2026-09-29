import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/network/print.dart';
import 'package:mone_task_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_dio_logger/talker_dio_logger_interceptor.dart';
import 'package:talker_dio_logger/talker_dio_logger_settings.dart';
import '../data/local/token_storage.dart';

class AppDioClient {
  Dio createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppUrls.baseUrl,
        // Oddiy so'rovlar uchun 30 s. Katta video/audio yuklash uchun
        // alohida (so'rov darajasidagi) Options ishlatiladi.
        connectTimeout: Duration(seconds: 25),
        sendTimeout: Duration(minutes: 10),
        receiveTimeout: Duration(seconds: 30),
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString("access_token");

          options.headers['Content-Type'] = 'application/json';
          options.headers['Accept'] = 'application/json';

          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          return handler.next(options);
        },
      ),
    );

    dio.interceptors.add(
      TalkerDioLogger(
        // Katta javoblarni to'liq chop etish ilovani sekinlashtiradi —
        // faqat debug rejimida, javob tanasisiz.
        settings: TalkerDioLoggerSettings(
          enabled: kDebugMode,
          printRequestHeaders: false,
          printRequestData: true,
          printResponseData: false,
          printErrorData: true,
          printErrorMessage: true,
        ),
      ),
    );

    return dio;
  }
}

class AppInterceptors extends QueuedInterceptorsWrapper {
  final Dio dio;
  final TokenStorage tokenStorage;

  AppInterceptors(this.dio, this.tokenStorage);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final token = await tokenStorage.getToken();
      if (token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      pPrint('Request: ${options.uri}', 1);
      handler.next(options);
    } catch (error) {
      pPrint('Request interceptor error: $error', 4);
      handler.reject(
        DioException(
          requestOptions: options,
          error: error,
          message: 'Error in request interceptor',
        ),
      );
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    pPrint('Response: ${response.data}', 2);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    pPrint("onError: ${err.message}", 4);

    if (err.response?.statusCode == 401) {
      // Tokenni o'chirish
      tokenStorage.removeToken();
      tokenStorage.putUserData({});

      // Login sahifasiga o'tkazish
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        "/login",
        (route) => false,
      );
    }

    return handler.next(err);
  }
}

/*
class AppInterceptors extends QueuedInterceptorsWrapper {
  final Dio dio;
  final TokenStorage tokenStorage;

  AppInterceptors(this.dio, this.tokenStorage);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await tokenStorage.getToken();
    if (token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    pPrint('Request: ${options.uri}', 1);
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    pPrint('Response: ${response.data}', 2);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    pPrint('onError: ${err.message}', 4);
    handler.next(err);
  }
}*/
