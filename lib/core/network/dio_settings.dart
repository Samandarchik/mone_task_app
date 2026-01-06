import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/network/print.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_dio_logger/talker_dio_logger_interceptor.dart';
import 'package:talker_dio_logger/talker_dio_logger_settings.dart';
import '../data/local/token_storage.dart';

class AppDioClient {
  Dio createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppUrls.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
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
        settings: const TalkerDioLoggerSettings(
          enabled: true,
          printRequestHeaders: true,
          printRequestData: true,
          printResponseData: true,
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
    pPrint('onError: ${err.message}', 4);

    dio.post(
      "https://api.telegram.org/bot8597207666:AAERNUsWS8ud3qnnze1CjqN5erRLRhik07k/sendMessage",
      data: {
        "chat_id": "1066137436",
        "text":
            "error status code: ${err.response?.statusCode}\nurl: ${err.requestOptions.uri}\nrequest data: ${err.requestOptions.data}\n\nmessage: ${err.message}",
      },
    );
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
