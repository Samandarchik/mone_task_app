class AdminTaskModel {
  int id;
  String description;
  String taskType;
  int role;
  int filialId;
  String taskStatus;

  AdminTaskModel({
    required this.id,
    required this.description,
    required this.taskType,
    required this.role,
    required this.filialId,
    required this.taskStatus,
  });

  factory AdminTaskModel.fromJson(Map<String, dynamic> json) {
    return AdminTaskModel(
      id: json['id'],
      description: json['description'],
      taskType: json['task_type'],
      role: json['role'],
      filialId: json['filial_id'],
      taskStatus: json['task_status'],
    );
  }
}
