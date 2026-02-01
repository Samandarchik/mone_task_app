class TaskWorkerModel {
  final int id;
  final String description;
  final int taskType;
  final int taskStatus;
  final String? videoUrl;
  final List<int>? days;
  final String? notificationTime;

  TaskWorkerModel({
    required this.id,
    required this.description,
    required this.taskType,
    required this.taskStatus,
    this.videoUrl,
    this.days,
    this.notificationTime,
  });

  factory TaskWorkerModel.fromJson(Map<String, dynamic> json) {
    return TaskWorkerModel(
      id: json['taskId'],
      description: json['task'],
      taskType: json['type'],
      taskStatus: json['status'],
      videoUrl: json["videoUrl"],
      days: json['days'] != null ? List<int>.from(json['days']) : null,
      notificationTime: json['notificationTime'],
    );
  }
}
