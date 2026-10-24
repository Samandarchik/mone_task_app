import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';

/// Workly'dan olingan davomat: foydalanuvchi bugun ishga kelganmi.
class AttendanceItem {
  final int userId;
  final String username;
  final String role;
  final String phone;
  final List<int> filialIds;
  final bool hasPhone;
  final bool came;
  final DateTime? inTime;
  final DateTime? outTime;
  final bool open;
  final int workedSeconds;

  AttendanceItem({
    required this.userId,
    required this.username,
    required this.role,
    required this.phone,
    required this.filialIds,
    required this.hasPhone,
    required this.came,
    required this.inTime,
    required this.outTime,
    required this.open,
    required this.workedSeconds,
  });

  static DateTime? _ts(dynamic v) {
    final n = v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
    return n > 0 ? DateTime.fromMillisecondsSinceEpoch(n * 1000) : null;
  }

  factory AttendanceItem.fromJson(Map<String, dynamic> json) {
    return AttendanceItem(
      userId: json['userId'] ?? 0,
      username: json['username'] ?? '',
      role: json['role'] ?? '',
      phone: json['phone'] ?? '',
      filialIds: (json['filialIds'] as List?)?.cast<int>() ?? const [],
      hasPhone: json['hasPhone'] == true,
      came: json['came'] == true,
      inTime: _ts(json['inTs']),
      outTime: _ts(json['outTs']),
      open: json['open'] == true,
      workedSeconds: json['workedSeconds'] ?? 0,
    );
  }
}

class AttendanceService {
  final Dio _dio = sl<Dio>();

  /// [date] — `YYYY-MM-DD`, null bo'lsa bugun. Xato bo'lsa exception.
  Future<List<AttendanceItem>> fetch({String? date}) async {
    final response = await _dio.get(
      AppUrls.attendance,
      queryParameters: {if (date != null) 'date': date},
    );
    final data = response.data;
    if (data is Map && data['success'] == true) {
      return (data['data'] as List)
          .map((e) => AttendanceItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(data is Map ? data['error'] ?? 'Ошибка' : 'Ошибка');
  }
}
