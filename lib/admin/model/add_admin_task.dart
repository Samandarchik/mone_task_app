class AddAdminTaskModel {
  String task;
  int taskType;
  List<int> filialsId;
  List<int>? days;

  AddAdminTaskModel({
    required this.task,
    required this.taskType,
    required this.filialsId,
    this.days,
  });
  //to json
  Map<String, dynamic> toJson() => {
    "task": task,
    "type": taskType,
    "filialIds": filialsId,
    "days": days,
  };
}
