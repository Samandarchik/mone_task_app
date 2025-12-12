abstract final class AppUrls {
  static const String baseUrl = "http://127.0.0.1:8000";
  // static const String baseUrl = "http://localhost:1313";
  static const String login = '$baseUrl/login';
  static const String refresh = '$baseUrl/refresh';
  static const String workerTasks = '$baseUrl/worker/tasks/';
  static const String completeTask = '$baseUrl/worker/task-proofs/';
  static const String adminTasks = '$baseUrl/admin/tasks/';
  static const String addTask = '$baseUrl/admin/tasks/';
  static const String deleteTask = '$baseUrl/admin/tasks/';
  static const String roles = '$baseUrl/admin/roles/';
}
