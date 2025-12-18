abstract final class AppUrls {
  static const String baseUrl = "https://6d864bb82519.ngrok-free.app";
  // static const String baseUrl = "http://localhost:1313";
  static const String login = '$baseUrl/login';
  static const String refresh = '$baseUrl/refresh';
  static const String workerTasks = '$baseUrl/worker/tasks/';
  static const String completeTask = '$baseUrl/worker/task-proofs/';
  static const String adminTasks = '$baseUrl/admin/tasks/';
  static const String addTask = '$baseUrl/admin/tasks/';
  static const String deleteTask = '$baseUrl/admin/tasks/';
  static const String roles = '$baseUrl/admin/roles/';
  static const String taskProof = '$baseUrl/checker/task-proofs/';
}
