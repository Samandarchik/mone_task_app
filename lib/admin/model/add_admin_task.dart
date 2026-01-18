class AddAdminTaskModel {
  String task;
  int taskType;
  int role;
  List<int> filialsId;
  List<int>? days;

  AddAdminTaskModel({
    required this.task,
    required this.taskType,
    required this.role,
    required this.filialsId,
    this.days,
  });
  //to json
  Map<String, dynamic> toJson() => {
    "task": task,
    "type": taskType,
    "role": role,
    "filialIds": filialsId,
    "days": days,
  };
}
