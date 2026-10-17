/// Bitta yagona Task model — backend /api/tasks endpointdan keladi.
/// Barcha rollar (worker, checker, admin) shu modelni ishlatadi.
class TaskModel {
  int taskId;

  /// Shablon ID — kunlar bo'yicha o'zgarmaydi (pin va shaxsiy tartib uchun)
  int templateId;

  /// Joriy foydalanuvchi qadab qo'ygan
  bool pinned;
  String task;
  int type;
  int filialId;
  int? status;
  String? videoUrl;

  /// Barcha yuborilgan videolar (multiVideo bo'lsa bir nechta)
  List<String> videoUrls;

  /// Super admin yoqqan bo'lsa — taskka bir nechta video yuborish mumkin
  bool multiVideo;

  /// Super admin belgilagan videolar soni (kartada shuncha slot ko'rinadi)
  int videoCount;
  List<String> checkerAudioUrls;
  String? submittedBy;
  DateTime? submittedAt;
  String category;
  String? date;
  String? notificationTime;
  List<int>? days;

  TaskModel({
    required this.taskId,
    this.templateId = 0,
    this.pinned = false,
    required this.task,
    required this.type,
    this.filialId = 0,
    this.status,
    this.videoUrl,
    this.videoUrls = const [],
    this.multiVideo = false,
    this.videoCount = 1,
    this.checkerAudioUrls = const [],
    this.submittedBy,
    this.submittedAt,
    this.category = '',
    this.date,
    this.notificationTime,
    this.days,
  });

  /// Yuborilgan barcha videolar (eski bitta videoUrl ham hisobga olinadi)
  List<String> get allVideos => videoUrls.isNotEmpty
      ? videoUrls
      : (videoUrl != null && videoUrl!.isNotEmpty ? [videoUrl!] : const []);

  /// Kamida bitta video bormi
  bool get hasAnyVideo => allVideos.isNotEmpty;

  /// Super admin belgilagan barcha videolar yuklanganmi — shundagina vazifa tugaydi
  bool get videosComplete =>
      allVideos.isNotEmpty &&
      allVideos.length >= (videoCount < 1 ? 1 : videoCount);

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      taskId: json['taskId'] ?? 0,
      templateId: json['templateId'] ?? 0,
      pinned: json['pinned'] ?? false,
      task: json['task'] ?? '',
      type: json['type'] ?? 1,
      filialId: json['filialId'] ?? 0,
      status: json['status'],
      videoUrl: json['videoUrl'],
      videoUrls: json['videoUrls'] != null
          ? List<String>.from(json['videoUrls'])
          : (json['videoUrl'] != null ? [json['videoUrl'] as String] : []),
      multiVideo: json['multiVideo'] ?? false,
      videoCount: json['videoCount'] ?? 1,
      category: json['category'] ?? '',
      notificationTime: json['notificationTime'],
      days: json['days'] != null ? List<int>.from(json['days']) : null,
      submittedBy: json['submittedBy'],
      checkerAudioUrls: json['checkerAudioUrls'] != null
          ? List<String>.from(json['checkerAudioUrls'])
          : (json['checkerAudioUrl'] != null
                ? [json['checkerAudioUrl'] as String]
                : []),
      submittedAt: json['submittedAt'] != null
          ? DateTime.parse(json['submittedAt'])
          : null,
      date: json['date'],
    );
  }
}
