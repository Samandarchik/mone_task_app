class AdminTaskModel {
  int taskId;
  int filialId;
  String task;
  int type;
  int status;
  String? videoUrl;

  AdminTaskModel({
    required this.taskId,
    required this.task,
    required this.type,
    required this.filialId,
    required this.status,
    this.videoUrl,
  });

  factory AdminTaskModel.fromJson(Map<String, dynamic> json) {
    return AdminTaskModel(
      taskId: json['taskId'],
      task: json['task'],
      type: json['type'],
      filialId: json['filialId'],
      status: json['status'],
      videoUrl: json["videoUrl"],
    );
  }
}
