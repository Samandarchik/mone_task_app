class EditTaskUiModel {
  int taskId;
  String task;
  int taskType;
  int role;
  List<int> filialsId;
  List<int>? days;

  EditTaskUiModel({
    required this.taskId,
    required this.task,
    required this.taskType,
    required this.role,
    required this.filialsId,
    this.days,
  });
  //to json
  Map<String, dynamic> toJson() => {
    "description": task,
    "task_type": taskType,
    "role": role,
    "filials_id": filialsId,
    "days": days,
  };
}
