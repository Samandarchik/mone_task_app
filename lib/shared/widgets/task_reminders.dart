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
  final int taskId;
  final String filialName;
  final String task;
  final String time;
  final int lateMinutes;

  /// Kim bajarishi kerak (worker + biriktirilgan sotrudniklar)
  final List<String> responsible;

  /// Revizor talabi: oxirgi vaqti va necha marta (talab bo'lmasa null)
  final String? demandAt;
  final int demandCount;

  _OverdueTask.fromJson(Map<String, dynamic> json)
    : taskId = json['taskId'] ?? 0,
      filialName = json['filialName'] ?? '',
      task = json['task'] ?? '',
      time = json['time'] ?? '',
      lateMinutes = json['lateMinutes'] ?? 0,
      responsible = [
        for (final p in (json['responsible'] as List? ?? const []))
          if (p is Map) '${p['username'] ?? ''}',
      ],
      demandAt = json['demand'] is Map ? json['demand']['lastAt'] : null,
      demandCount = json['demand'] is Map ? (json['demand']['count'] ?? 0) : 0;
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

  /// Ochiq ro'yxat dialogini qayta chizish uchun (talabdan keyin)
  final _listVersion = ValueNotifier<int>(0);
  final Set<int> _demanding = {};

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
      } else if (name == 'task_demand_updated') {
        _load();
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
    _listVersion.dispose();
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
    _listVersion.value++;
  }

  /// Revizor talabi: xodimlarga majburiy oyna + Telegram
  Future<void> _demand(_OverdueTask t) async {
    if (_demanding.contains(t.taskId)) return;
    _demanding.add(t.taskId);
    _listVersion.value++;
    final messenger = ScaffoldMessenger.of(context);
    String msg;
    try {
      final response = await sl<Dio>().post(
        '${AppUrls.tasks}/${t.taskId}/demand',
      );
      final data = response.data is Map ? response.data : const {};
      final tg = data['telegram'] ?? 0;
      final noTg = (data['noTelegram'] as List?)?.join(', ') ?? '';
      msg = 'Потребовано. Telegram: $tg';
      if (noTg.isNotEmpty) msg += '\nБез Telegram: $noTg';
    } catch (e) {
      msg = 'Не удалось отправить';
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map && data['error'] != null) msg = '${data['error']}';
      }
    }
    _demanding.remove(t.taskId);
    await _load();
    messenger.showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
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
              child: SizedBox(
                width: 360,
                child: ValueListenableBuilder<int>(
                  valueListenable: _listVersion,
                  builder: (_, _, _) => _buildList(),
                ),
              ),
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
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
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
                    _demandRow(t),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Mas'ullar ismi + «Потребовать» tugmasi
  Widget _demandRow(_OverdueTask t) {
    final busy = _demanding.contains(t.taskId);
    final demanded = t.demandCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.responsible.isEmpty
                      ? 'Нет ответственного'
                      : '👤 ${t.responsible.join(', ')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: t.responsible.isEmpty
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF4B5563),
                  ),
                ),
                if (demanded)
                  Text(
                    'Потребовано ${t.demandAt ?? ''}'
                    '${t.demandCount > 1 ? ' (${t.demandCount}×)' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFD97706),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy || t.responsible.isEmpty ? null : () => _demand(t),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              visualDensity: VisualDensity.compact,
            ),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(demanded ? 'Ещё раз' : 'Потребовать'),
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

bool _demandDialogOpen = false;

/// Xodimga: revizor talab qilgan, hali bajarilmagan vazifalar.
/// Ilova ochilganda va WS "task_demand" kelganda chaqiriladi — talab bo'lsa
/// yopib bo'lmaydigan oyna chiqadi (faqat «Выполняю» bilan yopiladi; server
/// vazifa bajarilmaguncha har 10 daqiqada qayta yuboradi).
Future<void> checkMyDemands(BuildContext context) async {
  if (_demandDialogOpen) return;
  List list;
  try {
    final response = await sl<Dio>().get(AppUrls.myDemands);
    final data = response.data is Map ? response.data['data'] : null;
    if (data is! List || data.isEmpty) return;
    list = data;
  } catch (_) {
    return;
  }
  if (!context.mounted || _demandDialogOpen) return;

  _demandDialogOpen = true;
  SystemSound.play(SystemSoundType.alert);
  HapticFeedback.heavyImpact();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: const Color(0xFFFEF2F2),
        icon: const Icon(
          Icons.report_rounded,
          size: 48,
          color: Color(0xFFDC2626),
        ),
        title: const Text(
          'Ревизор требует выполнить',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in list)
                if (item is Map)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item['task'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${item['filialName'] ?? ''} · ⏰ ${item['time'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        Text(
                          'Требует: ${item['demandedBy'] ?? ''}, ${item['lastAt'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ),
              const Text(
                'Выполните задачу и загрузите видео. Напоминание будет '
                'приходить каждые 10 минут, пока задача не выполнена.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Выполняю'),
            ),
          ),
        ],
      ),
    ),
  );
  _demandDialogOpen = false;
}
