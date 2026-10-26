import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/network/ws_service.dart';
import 'package:mone_task_app/shared/services/task_prefs_service.dart';
import 'package:mone_task_app/shared/widgets/task_reorder_list.dart';

enum LoadingState { idle, loading, loaded, error }

class AdminTasksProvider extends ChangeNotifier {
  final TaskViewService _service = TaskViewService();
  StreamSubscription? _wsSub;

  // ── Filials ──────────────────────────────────────────────────────────────
  List<FilialModel> _filials = [];
  LoadingState _filialsState = LoadingState.idle;
  String? _filialsError;

  List<FilialModel> get filials => _filials;
  LoadingState get filialsState => _filialsState;
  String? get filialsError => _filialsError;

  // ── Tasks ────────────────────────────────────────────────────────────────
  List<TaskModel> _tasks = [];
  LoadingState _tasksState = LoadingState.idle;
  String? _tasksError;

  List<TaskModel> get tasks => _tasks;
  LoadingState get tasksState => _tasksState;
  String? get tasksError => _tasksError;

  // ── Selected date ────────────────────────────────────────────────────────
  DateTime _selectedDate = DateTime.now();
  DateTime get selectedDate => _selectedDate;

  // ── Status filter ────────────────────────────────────────────────────────
  Set<int> _selectedStatuses = {};
  Set<int> get selectedStatuses => _selectedStatuses;

  bool _filterNoVideo = false;
  bool get filterNoVideo => _filterNoVideo;

  bool _filterHasAudio = false;
  bool get filterHasAudio => _filterHasAudio;

  bool get isFilterActive =>
      _selectedStatuses.isNotEmpty || _filterNoVideo || _filterHasAudio;

  void toggleStatusFilter(int status) {
    if (_selectedStatuses.contains(status)) {
      _selectedStatuses.remove(status);
    } else {
      _selectedStatuses.add(status);
    }
    notifyListeners();
  }

  void toggleNoVideoFilter() {
    _filterNoVideo = !_filterNoVideo;
    notifyListeners();
  }

  /// Faqat ovozli xabar (golosovoy) yuklangan vazifalar
  void toggleHasAudioFilter() {
    _filterHasAudio = !_filterHasAudio;
    notifyListeners();
  }

  void clearStatusFilter() {
    _selectedStatuses = {};
    _filterNoVideo = false;
    _filterHasAudio = false;
    notifyListeners();
  }

  // ── MUHIM: setSelectedDate faqat date ni saqlaydi ─────────────────────
  // notifyListeners CHAQIRMAYMIZ — UI o'zi fetchTasks ni kutadi
  // Sana o'zgarganda faqat fetchTasks chaqiriladi, u tugagach UI yangilanadi
  void setSelectedDate(DateTime date) {
    _selectedDate = date;
    // Boshqa sananing vazifalari ko'rinib qolmasin (xato bo'lsa ham)
    _tasks = [];
    fetchTasks();
    // notifyListeners YO'Q — fetchTasks tugaganda o'zi chaqiradi
  }

  // ── Fetch filials ────────────────────────────────────────────────────────
  Future<void> fetchFilials() async {
    _filialsState = LoadingState.loading;
    _filialsError = null;
    notifyListeners(); // Bu init paytida chaqiriladi — muammo yo'q

    try {
      _filials = await _service.fetchFilials();
      _filialsState = LoadingState.loaded;
    } catch (e) {
      _filialsError = e.toString();
      _filialsState = LoadingState.error;
    }
    notifyListeners();
  }

  /// Filiallarni loading ko'rsatmasdan qayta oladi (masalan, tartib boshqa
  /// sahifada o'zgargandan keyin).
  Future<void> refreshFilials() async {
    try {
      _filials = await _service.fetchFilials();
      notifyListeners();
    } catch (_) {}
  }

  // ── Reorder filials ──────────────────────────────────────────────────────
  /// Tab sudralganda darhol yangi tartibni ko'rsatadi va serverga saqlaydi.
  /// Saqlanmasa — eski tartib qaytariladi.
  Future<bool> reorderFilials(List<FilialModel> order) async {
    final previous = _filials;
    _filials = order;
    notifyListeners();

    final ok = await TemplateService().reorderFilials(
      order.map((f) => f.filialId).toList(),
    );
    if (!ok) {
      _filials = previous;
      notifyListeners();
    }
    return ok;
  }

  // ── Fetch tasks ──────────────────────────────────────────────────────────
  // Har bir so'rovga raqam — eskirgan (keyin qaytgan) javob yangisini bosmasin
  int _fetchSeq = 0;

  Future<void> fetchTasks() async {
    // notifyListeners faqat fetch TUGAGACH chaqiriladi. Ro'yxat bor paytda
    // UI spinner ko'rsatmaydi (admin_task_ui), shuning uchun izoh/status
    // kelganda fonda yangilash ro'yxatni qayta yaratmaydi va scroll joyida qoladi.
    final seq = ++_fetchSeq;
    _tasksState = LoadingState.loading;
    _tasksError = null;

    try {
      final tasks = await _service.fetchTasks(_selectedDate);
      if (seq != _fetchSeq) return;
      _tasks = tasks;
      _tasksState = LoadingState.loaded;
    } catch (e) {
      if (seq != _fetchSeq) return;
      _tasksError = e.toString();
      _tasksState = LoadingState.error;
    }

    notifyListeners();
  }

  // ── Shaxsiy tartib ──────────────────────────────────────────────────────
  final TaskPrefsService _prefs = TaskPrefsService();

  /// Ko'rinib turgan ro'yxatda (filtr bilan ham) bosib turib sudrash
  Future<void> reorderVisible(
    List<TaskModel> visible,
    int oldIndex,
    int newIndex,
  ) async {
    final list = reordered(visible, oldIndex, newIndex);
    // Yo'lda turgan (eski tartibli) javob yangi tartibni bosib ketmasin
    _fetchSeq++;
    _tasks = mergeOrder(_tasks, list);
    notifyListeners();

    // Filial tartibi hamma uchun bitta — boshqalarda WS orqali yangilanadi
    final filialId = list.first.filialId;
    final ok = await _prefs.saveOrder(filialId, [
      for (final t in _tasks)
        if (t.filialId == filialId) t.templateId,
    ]);
    if (!ok) await fetchTasks();
  }

  // ── Filter tasks by filial + status ─────────────────────────────────────
  List<TaskModel> tasksForFilial(int filialId) {
    var filtered = _tasks.where((t) => t.filialId == filialId);

    if (_selectedStatuses.isNotEmpty) {
      filtered = filtered.where((t) => _selectedStatuses.contains(t.status));
    }

    if (_filterNoVideo) {
      filtered = filtered.where(
        (t) => t.videoUrl == null || t.videoUrl!.isEmpty,
      );
    }

    if (_filterHasAudio) {
      filtered = filtered.where((t) => t.checkerAudioUrls.isNotEmpty);
    }

    return filtered.toList();
  }

  // ── Delete task ──────────────────────────────────────────────────────────
  Future<bool> deleteTask(int taskId) async {
    try {
      final success = await _service.deleteTask(taskId);
      if (success) {
        _tasks.removeWhere((t) => t.taskId == taskId);
        notifyListeners();
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  // ── Update task status ───────────────────────────────────────────────────
  Future<bool> updateTaskStatus(int taskId, int status, DateTime date) async {
    try {
      final success = await _service.updateTaskStatus(
        taskId,
        status,
        date,
        null,
      );
      if (success) {
        final index = _tasks.indexWhere((t) => t.taskId == taskId);
        if (index != -1) {
          _tasks[index].status = status;
          notifyListeners();
        }
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  // ── WebSocket ────────────────────────────────────────────────────────────
  void initWs() {
    final ws = WsService();
    ws.connect();
    _wsSub?.cancel();
    _wsSub = ws.onEvent.listen((event) {
      if (event['event'] != 'task_updated') return;
      // O'zimiz sudragan tartib — ekranda allaqachon shunday
      if (isOwnOrderChange(event)) return;

      final data = event['data'];
      if (data == null) return;

      final action = data['action'] as String?;

      if (action == 'status_changed') {
        // Status o'zgarishi — lokal yangilash (fetchTasks kerak emas)
        final taskIdRaw = data['taskId'];
        final statusRaw = data['status'];
        if (taskIdRaw != null && statusRaw != null) {
          final taskId = taskIdRaw is int
              ? taskIdRaw
              : int.tryParse('$taskIdRaw');
          final status = statusRaw is int
              ? statusRaw
              : int.tryParse('$statusRaw');
          if (taskId != null && status != null) {
            final idx = _tasks.indexWhere((t) => t.taskId == taskId);
            if (idx != -1) {
              _tasks[idx].status = status;
              notifyListeners();
            }
          }
        }
      } else {
        // audio_comment, audio_deleted, video_submitted, video_merged
        // Yangi URL kerak — backenddan yuklash
        fetchTasks();
      }
    });
  }

  // ── Initial load ─────────────────────────────────────────────────────────
  Future<void> init() async {
    initWs();
    await Future.wait([fetchFilials(), fetchTasks()]);
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }
}
