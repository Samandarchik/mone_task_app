abstract final class AppUrls {
  static const String baseUrl = "https://task.monebakeryuz.uz";
  // static const String baseUrl = "http://localhost:8000";
  static const String login = '$baseUrl/api/auth/login';
  static const String refresh = '$baseUrl/refresh';
  static const String tasks = '$baseUrl/api/tasks';
  static const String deleteTask = '$baseUrl/admin/tasks/';
  static const String roles = '$baseUrl/admin/roles/';
}
