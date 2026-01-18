class EditTaskUiModel {
  int taskId;
  String task;
  int taskType;
  List<int> filialsId;
  List<int>? days;

  EditTaskUiModel({
    required this.taskId,
    required this.task,
    required this.taskType,
    required this.filialsId,
    this.days,
  });
  //to json
  Map<String, dynamic> toJson() => {
    "task": task,
    "type": taskType,
    "days": days,
  };
}
