import 'package:flutter/foundation.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';

enum LoadingState { idle, loading, loaded, error }

class AdminTasksProvider extends ChangeNotifier {
  final AdminTaskService _service = AdminTaskService();

  // ── Filials ──────────────────────────────────────────────────────────────
  List<FilialModel> _filials = [];
  LoadingState _filialsState = LoadingState.idle;
  String? _filialsError;

  List<FilialModel> get filials => _filials;
  LoadingState get filialsState => _filialsState;
  String? get filialsError => _filialsError;

  // ── Tasks ────────────────────────────────────────────────────────────────
  List<CheckerCheckTaskModel> _tasks = [];
  LoadingState _tasksState = LoadingState.idle;
  String? _tasksError;

  List<CheckerCheckTaskModel> get tasks => _tasks;
  LoadingState get tasksState => _tasksState;
  String? get tasksError => _tasksError;

  // ── Selected date ────────────────────────────────────────────────────────
  DateTime _selectedDate = DateTime.now();
  DateTime get selectedDate => _selectedDate;

  // ── Status filter ────────────────────────────────────────────────────────
  Set<int> _selectedStatuses = {};
  Set<int> get selectedStatuses => _selectedStatuses;
  bool get isFilterActive => _selectedStatuses.isNotEmpty;

  void toggleStatusFilter(int status) {
    if (_selectedStatuses.contains(status)) {
      _selectedStatuses.remove(status);
    } else {
      _selectedStatuses.add(status);
    }
    notifyListeners();
  }

  void clearStatusFilter() {
    _selectedStatuses = {};
    notifyListeners();
  }

  // ── MUHIM: setSelectedDate faqat date ni saqlaydi ─────────────────────
  // notifyListeners CHAQIRMAYMIZ — UI o'zi fetchTasks ni kutadi
  // Sana o'zgarganda faqat fetchTasks chaqiriladi, u tugagach UI yangilanadi
  void setSelectedDate(DateTime date) {
    _selectedDate = date;
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

  // ── Fetch tasks ──────────────────────────────────────────────────────────
  Future<void> fetchTasks() async {
    // ❌ OLDIN: _tasksState = LoadingState.loading + notifyListeners()
    //    Bu sana tanlanganda darhol rebuild → dialog yopilardi
    //
    // ✅ ENDI: loading state ni silent o'zgartirамiz,
    //    notifyListeners faqat fetch TUGAGACH chaqiriladi
    _tasksState = LoadingState.loading;
    _tasksError = null;
    // notifyListeners() — BU YERDA CHAQIRMAYMIZ

    try {
      _tasks = await _service.fetchTasks(_selectedDate);
      _tasksState = LoadingState.loaded;
    } catch (e) {
      _tasksError = e.toString();
      _tasksState = LoadingState.error;
    }

    // Faqat tugagach bir marta notify — bu paytda dialog allaqachon yopilgan
    notifyListeners();
  }

  // ── Filter tasks by filial + status ─────────────────────────────────────
  List<CheckerCheckTaskModel> tasksForFilial(int filialId) {
    var filtered = _tasks.where((t) => t.filialId == filialId);

    if (_selectedStatuses.isNotEmpty) {
      filtered = filtered.where((t) => _selectedStatuses.contains(t.status));
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

  // ── Initial load ─────────────────────────────────────────────────────────
  Future<void> init() async {
    await Future.wait([fetchFilials(), fetchTasks()]);
  }
}
