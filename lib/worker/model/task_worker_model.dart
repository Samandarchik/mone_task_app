class TaskWorkerModel {
  int id;
  String description;
  int taskType;
  int? taskStatus;
  String? submittedBy;
  DateTime? submittedAt;
  List<String> checkerAudioUrls;
  String? videoUrl;
  List<int>? days;

  TaskWorkerModel({
    required this.id,
    required this.description,
    required this.taskType,
    this.taskStatus,
    this.submittedBy,
    this.submittedAt,
    this.checkerAudioUrls = const [],
    this.videoUrl,
    this.days,
  });

  factory TaskWorkerModel.fromJson(Map<String, dynamic> json) {
    return TaskWorkerModel(
      id: json['taskId'],
      description: json['task'],
      taskType: json['type'],
      taskStatus: json['status'],
      videoUrl: json["videoUrl"],
      submittedBy: json['submittedBy'],
      checkerAudioUrls: json['checkerAudioUrls'] != null
          ? List<String>.from(json['checkerAudioUrls'])
          : (json['checkerAudioUrl'] != null ? [json['checkerAudioUrl'] as String] : []),
      submittedAt: json['submittedAt'] != null
          ? DateTime.parse(json['submittedAt'])
          : null,
      days: json['days'] != null ? List<int>.from(json['days']) : null,
    );
  }
}
