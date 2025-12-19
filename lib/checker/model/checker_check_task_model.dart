class CheckerCheckTaskModel {
  int? id;
  int? taskId;
  String? description;
  String? taskType;
  int? filialId;
  String? taskStatus;
  String? filePath;
  String? createdDate;

  CheckerCheckTaskModel({
    this.id,
    this.taskId,
    this.description,
    this.taskType,
    this.filialId,
    this.taskStatus,
    this.filePath,
    this.createdDate,
  });

  CheckerCheckTaskModel.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    taskId = json['task_id'];
    description = json['description'];
    taskType = json['task_type'];
    filialId = json['filial_id'];
    taskStatus = json['task_status'];
    filePath = json['file_path'];
    createdDate = json['created_date'];
  }
}

// flutter: \^[[38;5;46m│     "task_id": 58,\^[[0m
// flutter: \^[[38;5;46m│     "description": "Хоз тавар ва напиткаларни руйхат билан текшириш ва тулдириш",\^[[0m
// flutter: \^[[38;5;46m│     "task_type": "daily",\^[[0m
// flutter: \^[[38;5;46m│     "role": 3,\^[[0m
// flutter: \^[[38;5;46m│     "filial_id": 1,\^[[0m
// flutter: \^[[38;5;46m│     "task_status": "checking",\^[[0m
// flutter: \^[[38;5;46m│     "file_path": "uploads/2025-12-11/1765464944.363488.jpg",\^[[0m
// flutter: \^[[38;5;46m│     "created_date": "2025-12-11"\^[[0m
