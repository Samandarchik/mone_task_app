class AddAdminTaskModel {
  String task;
  int taskType;
  List<int> filialsId;
  List<int>? days;
  String? category;
  bool multiVideo;
  int videoCount;

  AddAdminTaskModel({
    required this.task,
    required this.taskType,
    required this.filialsId,
    this.days,
    this.category,
    this.multiVideo = false,
    this.videoCount = 1,
  });
  //to json
  Map<String, dynamic> toJson() => {
    "task": task,
    "type": taskType,
    "filialIds": filialsId,
    "days": days,
    "category": category,
    "multiVideo": multiVideo,
    "videoCount": videoCount,
  };
}
