abstract final class AppUrls {
  static const String baseUrl = "https://taskapi.monebakeryuz.uz";
  // static const String baseUrl = "http://192.168.0.107:8000";
  // static const String baseUrl = "http://localhost:8000";
  static const String login = '$baseUrl/api/auth/login';
  static const String register = '$baseUrl/api/auth/register';
  static const String logOut = '$baseUrl/api/auth/logout';
  static const String refresh = '$baseUrl/refresh';
  static const String tasks = '$baseUrl/api/tasks';
  static const String tasksAll = '$baseUrl/api/tasks/all';
  static const String deleteTask = '$baseUrl/api/tasks';
  static const String roles = '$baseUrl/admin/roles/';
  static const String filial = '$baseUrl/api/filials';
  static const String users = '$baseUrl/api/users';
  static const String reorder = '$baseUrl/api/tasks/reorder';
  static const String notifications = '$baseUrl/api/notifications';
  static const String categories = '$baseUrl/api/categories';
  static const String forceLogout = '$baseUrl/api/auth/force-logout';
  static const String reportsExcel = '/api/reports/excel';
}

//vidio alish shavad navasha mondan
