import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';

/// Worker qo'shgan yordamchi xodim (Сотрудник).
class EmployeeModel {
  final int userId;
  final String username;
  final String login;
  final String password;

  /// Unga biriktirilgan vazifa shablonlari
  final List<int> templateIds;

  EmployeeModel({
    required this.userId,
    required this.username,
    required this.login,
    required this.password,
    this.templateIds = const [],
  });

  factory EmployeeModel.fromJson(Map<String, dynamic> json) => EmployeeModel(
    userId: json['userId'] ?? 0,
    username: json['username'] ?? '',
    login: json['login'] ?? '',
    password: json['password'] ?? '',
    templateIds: json['templateIds'] != null
        ? List<int>.from(json['templateIds'])
        : const [],
  );
}

/// Worker o'z sotrudniklarini boshqaradi va vazifalarini ularga biriktiradi.
/// Xato bo'lsa server matni bilan [Exception] tashlanadi.
class EmployeeService {
  final Dio _dio = sl<Dio>();

  Future<List<EmployeeModel>> fetchEmployees() async {
    final response = await _call(() => _dio.get(AppUrls.myEmployees));
    final data = response.data['data'];
    if (data is! List) return [];
    return data.map((e) => EmployeeModel.fromJson(e)).toList();
  }

  Future<void> createEmployee({
    required String username,
    required String login,
    required String password,
  }) => _call(
    () => _dio.post(
      AppUrls.myEmployees,
      data: {'username': username, 'login': login, 'password': password},
    ),
  );

  /// Bo'sh qiymatlar o'zgartirilmaydi
  Future<void> updateEmployee(int id, {String? username, String? password}) =>
      _call(
        () => _dio.put(
          '${AppUrls.myEmployees}/$id',
          data: {
            if (username != null && username.isNotEmpty) 'username': username,
            if (password != null && password.isNotEmpty) 'password': password,
          },
        ),
      );

  Future<void> deleteEmployee(int id) =>
      _call(() => _dio.delete('${AppUrls.myEmployees}/$id'));

  /// Vazifani [employeeIds] ga biriktiradi (bo'sh — hammasidan olinadi)
  Future<void> setDelegation(int templateId, List<int> employeeIds) => _call(
    () => _dio.put(
      '${AppUrls.myDelegations}/$templateId',
      data: {'employeeIds': employeeIds},
    ),
  );

  Future<Response> _call(Future<Response> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      final data = e.response?.data;
      final message = data is Map && data['error'] != null
          ? '${data['error']}'
          : 'Ошибка сети';
      throw Exception(message);
    }
  }
}
