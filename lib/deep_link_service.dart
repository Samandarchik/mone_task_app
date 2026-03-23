/// Deep link dan kelgan task ma'lumotlari
class DeepLinkData {
  final String date;
  final int taskId;

  const DeepLinkData({required this.date, required this.taskId});

  @override
  String toString() => 'DeepLinkData(date: $date, taskId: $taskId)';
}

/// Deep link ni parse qilish
/// Format: https://taskapi.monebakeryuz.uz/task/2026-03-07/62
DeepLinkData? parseDeepLink(Uri uri) {
  try {
    // Path segments: ["task", "2026-03-07", "62"]
    final segments = uri.pathSegments;
    if (segments.length < 3 || segments[0] != 'task') return null;

    final date = segments[1]; // "2026-03-07"
    final taskId = int.tryParse(segments[2]); // 62

    if (taskId == null) return null;

    // Date formatini tekshirish (YYYY-MM-DD)
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return null;

    return DeepLinkData(date: date, taskId: taskId);
  } catch (_) {
    return null;
  }
}

/// Task uchun share link yaratish
String createTaskLink(String? date, int taskId) {
  final d = date ?? DateTime.now().toIso8601String().substring(0, 10);
  return 'https://taskapi.monebakeryuz.uz/task/$d/$taskId';
}
