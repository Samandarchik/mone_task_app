class CheckerCheckTaskModel {
  int taskId;
  String task;
  int type;
  int filialId;
  int status;
  String? videoUrl;
  List<int>? days;

  CheckerCheckTaskModel({
    required this.taskId,
    required this.task,
    required this.type,
    required this.filialId,
    required this.status,
    this.videoUrl,
    this.days,
  });

  factory CheckerCheckTaskModel.fromJson(Map<String, dynamic> json) {
    return CheckerCheckTaskModel(
      taskId: json['taskId'],
      task: json['task'],
      type: json['type'],
      filialId: json['filialId'],
      status: json['status'],
      videoUrl: json["videoUrl"],
      days: json["days"] != null ? List<int>.from(json["days"]) : null,
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
