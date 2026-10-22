import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/core/network/ws_service.dart';

/// Xodimga: vazifa vaqti keldi (server WS "task_reminder" yuboradi).
void showTaskReminder(BuildContext context, Map<String, dynamic> data) {
  SystemSound.play(SystemSoundType.alert);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 10),
      backgroundColor: const Color(0xFF1F2937),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: Row(
        children: [
          const Icon(Icons.alarm_rounded, color: Color(0xFFFBBF24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Время выполнить задачу · ${data['time'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFD1D5DB),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${data['task'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      action: SnackBarAction(label: 'OK', onPressed: () {}),
    ),
  );
}

class _OverdueTask {
  final String filialName;
  final String task;
  final String time;
  final int lateMinutes;

  _OverdueTask.fromJson(Map<String, dynamic> json)
    : filialName = json['filialName'] ?? '',
      task = json['task'] ?? '',
      time = json['time'] ?? '',
      lateMinutes = json['lateMinutes'] ?? 0;
}

String _lateText(int minutes) {
  if (minutes < 60) return '$minutes мин';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h ч' : '$h ч $m мин';
}

/// Korrektor uchun 🔔: vaqti o'tib, hali bajarilmagan vazifalar.
/// Server har 10 daqiqada WS "overdue_tasks" yuboradi — son yangilanadi va
/// ekranda xabar chiqadi. Bosilsa — tugma tagida ro'yxat.
class OverdueBellButton extends StatefulWidget {
  const OverdueBellButton({super.key});

  @override
  State<OverdueBellButton> createState() => _OverdueBellButtonState();
}

class _OverdueBellButtonState extends State<OverdueBellButton> {
  List<_OverdueTask> _tasks = const [];
  StreamSubscription? _sub;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = WsService().onEvent.listen((event) {
      final name = event['event'];
      if (name == 'overdue_tasks') {
        final data = event['data'];
        final list = data is Map ? data['tasks'] : null;
        if (list is List) {
          _setTasks(list);
          _announce();
        }
      } else if (name == 'task_updated') {
        // Video yuklangan bo'lishi mumkin — ro'yxatni yangilaymiz
        _refreshDebounce?.cancel();
        _refreshDebounce = Timer(const Duration(seconds: 2), _load);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await sl<Dio>().get('${AppUrls.tasks}/overdue');
      final list = response.data is Map ? response.data['data'] : null;
      if (list is List) _setTasks(list);
    } catch (_) {}
  }

  void _setTasks(List list) {
    if (!mounted) return;
    setState(() {
      _tasks = [
        for (final item in list)
          if (item is Map)
            _OverdueTask.fromJson(Map<String, dynamic>.from(item)),
      ];
    });
  }

  void _announce() {
    if (!mounted || _tasks.isEmpty) return;
    SystemSound.play(SystemSoundType.alert);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        backgroundColor: const Color(0xFF7F1D1D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            const Icon(Icons.notifications_active_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Не выполнено вовремя: ${_tasks.length}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Показать',
          textColor: Colors.white,
          onPressed: () => _openList(),
        ),
      ),
    );
  }

  /// Ro'yxat — qo'ng'iroqcha tagida, o'ng chetiga tekislangan
  void _openList() {
    if (!mounted) return;
    _load();
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final right = (screenWidth - origin.dx - box.size.width).clamp(
      8.0,
      screenWidth,
    );

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (_) => Stack(
        children: [
          Positioned(
            top: origin.dy + box.size.height + 6,
            right: right,
            child: Material(
              color: Colors.white,
              elevation: 10,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(width: 340, child: _buildList()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_active_rounded,
            size: 18,
            color: Color(0xFFDC2626),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Не выполнено вовремя',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '${_tasks.length}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );

    if (_tasks.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 8, 14, 20),
            child: Text(
              'Все задачи выполнены вовремя 👍',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _tasks.length,
              itemBuilder: (_, i) {
                final t = _tasks[i];
                final newFilial =
                    i == 0 || _tasks[i - 1].filialName != t.filialName;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (newFilial)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                        child: Text(
                          t.filialName.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              t.task,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '⏰ ${t.time}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                              Text(
                                '+${_lateText(t.lateMinutes)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _tasks.length;
    return Tooltip(
      message: 'Не выполнено вовремя',
      child: IconButton(
        onPressed: _openList,
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          backgroundColor: const Color(0xFFDC2626),
          child: Icon(
            count > 0
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            color: count > 0 ? const Color(0xFFDC2626) : null,
          ),
        ),
      ),
    );
  }
}
