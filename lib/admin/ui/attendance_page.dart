import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/attendance_service.dart';

/// Kim ishga kelgan (Workly davomati) — super_admin uchun.
class AttendancePage extends StatefulWidget {
  final List<FilialModel> filials;

  const AttendancePage({super.key, required this.filials});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final _service = AttendanceService();
  String _query = '';
  bool _loading = true;
  String? _error;
  List<AttendanceItem> _items = [];
  Timer? _autoRefresh;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _hm(DateTime? t) =>
      t == null ? '--:--' : '${_two(t.hour)}:${_two(t.minute)}';

  static String _duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '$hч $mм' : '$mм';
  }

  @override
  void initState() {
    super.initState();
    _load();
    // Bugungi davomat jonli o'zgaradi (kelish/ketish) — har daqiqada jim yangilaymiz.
    _autoRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_loading) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await _service.fetch();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || silent) return;
      String msg = 'Не удалось загрузить данные';
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map && data['error'] != null) msg = '${data['error']}';
      }
      setState(() {
        _error = msg;
        _loading = false;
      });
    }
  }

  String _filialNames(List<int> ids) {
    final names = widget.filials
        .where((f) => ids.contains(f.filialId))
        .map((f) => f.name)
        .toList();
    return names.join(', ');
  }

  List<AttendanceItem> get _visible {
    final q = _query.trim().toLowerCase();
    return _items.where((e) {
      if (q.isNotEmpty &&
          !e.username.toLowerCase().contains(q) &&
          !e.phone.contains(q)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Кто пришёл на работу'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Поиск по имени или телефону',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    final items = _visible;
    if (items.isEmpty) {
      return const Center(child: Text('Нет данных'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => _tile(items[i]),
      ),
    );
  }

  Widget _tile(AttendanceItem e) {
    // Ketgan — sariq, ishda — yashil, kelmagan — qizil, telefonsiz — kulrang.
    final left = e.came && !e.open;
    final color = e.came
        ? (left ? Colors.amber.shade700 : Colors.green)
        : (e.hasPhone ? Colors.red : Colors.grey);
    final filials = _filialNames(e.filialIds);

    String status;
    if (e.came) {
      status = e.open
          ? 'Пришёл ${_hm(e.inTime)} · на работе'
          : 'Пришёл ${_hm(e.inTime)} · ушёл ${_hm(e.outTime)}';
    } else if (!e.hasPhone) {
      status = 'Нет телефона — не связан с Workly';
    } else {
      status = 'Не пришёл';
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(
          e.came ? (left ? Icons.logout : Icons.check_circle) : Icons.cancel,
          color: color,
        ),
      ),
      title: Text(e.username, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        filials.isEmpty ? status : '$status\n$filials',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: e.came
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _hm(e.inTime),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: color,
                  ),
                ),
                if (!e.open && e.outTime != null)
                  Text(
                    'ушёл ${_hm(e.outTime)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                if (e.workedSeconds > 0)
                  Text(
                    _duration(e.workedSeconds),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            )
          : null,
    );
  }
}
