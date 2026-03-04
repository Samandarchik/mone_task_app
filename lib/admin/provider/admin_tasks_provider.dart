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

  void setSelectedDate(DateTime date) {
    _selectedDate = date;
    fetchTasks();
  }

  // ── Fetch filials ────────────────────────────────────────────────────────
  Future<void> fetchFilials() async {
    _filialsState = LoadingState.loading;
    _filialsError = null;
    notifyListeners();

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
    _tasksState = LoadingState.loading;
    _tasksError = null;
    notifyListeners();

    try {
      _tasks = await _service.fetchTasks(_selectedDate);
      _tasksState = LoadingState.loaded;
    } catch (e) {
      _tasksError = e.toString();
      _tasksState = LoadingState.error;
    }
    notifyListeners();
  }

  // ── Filter tasks by filial ──────────────────────────────────────────────
  List<CheckerCheckTaskModel> tasksForFilial(int filialId) {
    return _tasks.where((t) => t.filialId == filialId).toList();
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

  // ── Update task status ──────────────────────────────────────────────────
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

  // ── Initial load ────────────────────────────────────────────────────────
  Future<void> init() async {
    await Future.wait([fetchFilials(), fetchTasks()]);
  }
}
