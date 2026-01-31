class CheckerCheckTaskModel {
  int taskId;
  String task;
  String? submittedBy;
  DateTime? submittedAt;
  String? date;
  int type;
  int filialId;
  int status;
  String? notificationTime;
  String? videoUrl;
  List<int>? days;

  CheckerCheckTaskModel({
    required this.taskId,
    required this.task,
    required this.type,
    required this.filialId,
    required this.status,
    this.notificationTime,
    this.videoUrl,
    this.days,
    this.submittedBy,
    this.submittedAt,
    this.date,
  });

  factory CheckerCheckTaskModel.fromJson(Map<String, dynamic> json) {
    return CheckerCheckTaskModel(
      taskId: json['taskId'],
      task: json['task'],
      type: json['type'],
      filialId: json['filialId'],
      status: json['status'],
      videoUrl: json["videoUrl"],
      notificationTime: json["notificationTime"] ?? "12:00",
      days: json["days"] != null ? List<int>.from(json["days"]) : null,
      submittedBy: json["submittedBy"],
      submittedAt: json["submittedAt"] != null
          ? DateTime.parse(json["submittedAt"])
          : null,
      date: json["date"],
    );
  }

  // copy with
  CheckerCheckTaskModel copyWith({
    int? taskId,
    String? task,
    int? type,
    int? filialId,
    int? status,
    String? videoUrl,
  }) => CheckerCheckTaskModel(
    taskId: taskId ?? this.taskId,
    task: task ?? this.task,
    type: type ?? this.type,
    filialId: filialId ?? this.filialId,
    status: status ?? this.status,
    videoUrl: videoUrl ?? this.videoUrl,
  );
}
