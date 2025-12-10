class TaskWorkerModel {
  int id;
  String description;
  String taskType;
  int role;
  int filialId;
  String taskStatus;

  TaskWorkerModel({
    required this.id,
    required this.description,
    required this.taskType,
    required this.role,
    required this.filialId,
    required this.taskStatus,
  });

  factory TaskWorkerModel.fromJson(Map<String, dynamic> json) {
    return TaskWorkerModel(
      id: json['id'],
      description: json['description'],
      taskType: json['task_type'],
      role: json['role'],
      filialId: json['filial_id'],
      taskStatus: json['task_status'],
    );
  }
}
