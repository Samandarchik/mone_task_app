/// Bitta yagona Task model — backend /api/tasks endpointdan keladi.
/// Barcha rollar (worker, checker, admin) shu modelni ishlatadi.
class TaskModel {
  int taskId;
  String task;
  int type;
  int filialId;
  int? status;
  String? videoUrl;
  List<String> checkerAudioUrls;
  String? submittedBy;
  DateTime? submittedAt;
  String category;
  String? date;
  String? notificationTime;
  List<int>? days;

  TaskModel({
    required this.taskId,
    required this.task,
    required this.type,
    this.filialId = 0,
    this.status,
    this.videoUrl,
    this.checkerAudioUrls = const [],
    this.submittedBy,
    this.submittedAt,
    this.category = '',
    this.date,
    this.notificationTime,
    this.days,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      taskId: json['taskId'] ?? 0,
      task: json['task'] ?? '',
      type: json['type'] ?? 1,
      filialId: json['filialId'] ?? 0,
      status: json['status'],
      videoUrl: json['videoUrl'],
      category: json['category'] ?? '',
      notificationTime: json['notificationTime'],
      days: json['days'] != null ? List<int>.from(json['days']) : null,
      submittedBy: json['submittedBy'],
      checkerAudioUrls: json['checkerAudioUrls'] != null
          ? List<String>.from(json['checkerAudioUrls'])
          : (json['checkerAudioUrl'] != null
              ? [json['checkerAudioUrl'] as String]
              : []),
      submittedAt: json['submittedAt'] != null
          ? DateTime.parse(json['submittedAt'])
          : null,
      date: json['date'],
    );
  }
}
