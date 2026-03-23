class CheckerCheckTaskModel {
  int taskId;
  String task;
  String? submittedBy;
  DateTime? submittedAt;
  String category;
  String? date;
  int type;
  int filialId;
  int? status;
  String? notificationTime;
  String? videoUrl;
  List<String> checkerAudioUrls;
  List<int>? days;

  CheckerCheckTaskModel({
    required this.taskId,
    required this.task,
    required this.type,
    required this.filialId,
    this.status,
    this.notificationTime,
    this.videoUrl,
    this.days,
    this.submittedBy,
    this.submittedAt,
    this.checkerAudioUrls = const [],
    required this.category,
    this.date,
  });

  factory CheckerCheckTaskModel.fromJson(Map<String, dynamic> json) {
    return CheckerCheckTaskModel(
      taskId: json['taskId'],
      task: json['task'],
      type: json['type'],
      filialId: json['filialId'],
      status: json['status'],
      category: json['category'],
      videoUrl: json["videoUrl"],
      notificationTime: json["notificationTime"],
      days: json["days"] != null ? List<int>.from(json["days"]) : null,
      submittedBy: json["submittedBy"],
      checkerAudioUrls: json["checkerAudioUrls"] != null
          ? List<String>.from(json["checkerAudioUrls"])
          : (json["checkerAudioUrl"] != null ? [json["checkerAudioUrl"] as String] : []),
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
    category: category,
    type: type ?? this.type,
    filialId: filialId ?? this.filialId,
    status: status ?? this.status,
    videoUrl: videoUrl ?? this.videoUrl,
  );
}
