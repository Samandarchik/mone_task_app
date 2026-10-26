// ==================== MODEL ====================
class TemplateTaskModel {
  final int templateId;
  final String task;
  final int type; // 0: oylik, 1: kunlik, 2: haftalik, 3: oyning kunlari
  final List<int> filialIds;
  final int orderIndex;

  /// Joriy foydalanuvchining filial bo'yicha shaxsiy tartibi (filialId → kalit)
  final Map<int, int> positions;
  final List<int>? days;
  final String category;
  final String createdAt;
  final String? notificationTime;
  final bool multiVideo;
  final int videoCount;

  TemplateTaskModel({
    required this.templateId,
    required this.task,
    required this.type,
    required this.orderIndex,
    this.positions = const {},
    required this.filialIds,
    this.days,
    required this.createdAt,
    this.notificationTime,
    required this.category,
    this.multiVideo = false,
    this.videoCount = 1,
  });

  factory TemplateTaskModel.fromJson(Map<String, dynamic> json) {
    return TemplateTaskModel(
      templateId: json['templateId'] ?? 0,
      task: json['task'] ?? '',
      type: json['type'] ?? 0,
      orderIndex: json['orderIndex'] ?? 1,
      positions: {
        for (final e in ((json['positions'] as Map?) ?? const {}).entries)
          int.parse('${e.key}'): (e.value as num).toInt(),
      },
      filialIds: List<int>.from(json['filialIds'] ?? []),
      days: json['days'] != null ? List<int>.from(json['days']) : null,
      createdAt: json['createdAt'] ?? '',
      category: json['category'],
      notificationTime: json['notificationTime'],
      multiVideo: json['multiVideo'] ?? false,
      videoCount: json['videoCount'] ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'templateId': templateId,
      'task': task,
      'type': type,
      'filialIds': filialIds,
      if (days != null) 'days': days,
      'createdAt': createdAt,
      if (notificationTime != null) 'notificationTime': notificationTime,
    };
  }
}

class TemplateTaskResponse {
  final List<TemplateTaskModel> data;
  final bool success;
  final int total;

  TemplateTaskResponse({
    required this.data,
    required this.success,
    required this.total,
  });

  factory TemplateTaskResponse.fromJson(Map<String, dynamic> json) {
    return TemplateTaskResponse(
      data: (json['data'] as List)
          .map((item) => TemplateTaskModel.fromJson(item))
          .toList(),
      success: json['success'] ?? false,
      total: json['total'] ?? 0,
    );
  }
}
