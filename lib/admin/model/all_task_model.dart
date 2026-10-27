// ==================== MODEL ====================
class TemplateTaskModel {
  final int templateId;
  final String task;
  final int type; // 0: oylik, 1: kunlik, 2: haftalik, 3: oyning kunlari
  final List<int> filialIds;
  final int orderIndex;
  final List<int>? days;
  final String category;
  final String createdAt;
  final String? notificationTime;
  final bool multiVideo;
  final int videoCount;

  /// Namuna video — vazifa qanday bajarilishi kerak (bo'lmasa null)
  final String? guideVideoUrl;

  TemplateTaskModel({
    required this.templateId,
    required this.task,
    required this.type,
    required this.orderIndex,
    required this.filialIds,
    this.days,
    required this.createdAt,
    this.notificationTime,
    required this.category,
    this.multiVideo = false,
    this.videoCount = 1,
    this.guideVideoUrl,
  });

  factory TemplateTaskModel.fromJson(Map<String, dynamic> json) {
    return TemplateTaskModel(
      templateId: json['templateId'] ?? 0,
      task: json['task'] ?? '',
      type: json['type'] ?? 0,
      orderIndex: json['orderIndex'] ?? 1,
      filialIds: List<int>.from(json['filialIds'] ?? []),
      days: json['days'] != null ? List<int>.from(json['days']) : null,
      createdAt: json['createdAt'] ?? '',
      category: json['category'],
      notificationTime: json['notificationTime'],
      multiVideo: json['multiVideo'] ?? false,
      videoCount: json['videoCount'] ?? 1,
      guideVideoUrl: (json['guideVideoUrl'] as String?)?.isNotEmpty == true
          ? json['guideVideoUrl']
          : null,
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
