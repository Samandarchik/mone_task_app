class EditTaskUiModel {
  final int taskId;
  final int taskType;
  final List<int> filialsId;
  final String task;
  final List<int>? days;
  final int? hour;
  final int? minute;
  final String? category;

  EditTaskUiModel({
    required this.taskId,
    required this.taskType,
    required this.filialsId,
    required this.task,
    this.days,
    this.hour,
    this.minute,
    this.category,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': taskType,
      'task': task,
      'days': days,
      "time": "$hour:$minute",
      // "filialIds": filialsId,
      "category": category,
    };
  }
}
