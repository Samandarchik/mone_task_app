class AddAdminTaskModel {
  String description;
  String taskType;
  int role;
  List<int> filialsId;

  AddAdminTaskModel({
    required this.description,
    required this.taskType,
    required this.role,
    required this.filialsId,
  });
}
