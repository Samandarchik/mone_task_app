class AddAdminTaskModel {
  String task;
  int taskType;
  List<int> filialsId;
  List<int>? days;
  String? category;

  AddAdminTaskModel({
    required this.task,
    required this.taskType,
    required this.filialsId,
    this.days,
    this.category,
  });
  //to json
  Map<String, dynamic> toJson() => {
    "task": task,
    "type": taskType,
    "filialIds": filialsId,
    "days": days,
    "category": category,
  };
}
