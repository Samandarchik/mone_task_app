import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/edit_task_ui_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/widgets/category_selector.dart';
import 'package:mone_task_app/admin/ui/widgets/task_type_selector.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';

class EditTaskUi extends StatefulWidget {
  final TaskModel task;
  const EditTaskUi({super.key, required this.task});

  @override
  State<EditTaskUi> createState() => _EditTaskUiState();
}

class _EditTaskUiState extends State<EditTaskUi> {
  final TemplateService _taskService = TemplateService();
  late TextEditingController _controller;
  final GlobalKey<CategorySelectorState> _categoryKey = GlobalKey();

  int? _selectedType;
  List<int> _selectedFilials = [];
  List<int> _selectedWeekDays = [];
  List<int> _selectedDays = [];
  int? _selectedCategoryId;
  int? _selectedHour;
  int? _selectedMinute;
  bool _showTimePicker = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.task);
    _selectedType = widget.task.type == 0 ? 1 : widget.task.type;
    _selectedFilials = [widget.task.filialId];
    _selectedDays = widget.task.days ?? [];
    _selectedWeekDays = widget.task.days ?? [];

    final time = widget.task.notificationTime;
    if (time != null && time != "null:null" && time.contains(':')) {
      final parts = time.split(':');
      _selectedHour = int.tryParse(parts[0]);
      _selectedMinute = int.tryParse(parts[1]);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCategorySelection();
    });
  }

  void _initCategorySelection() {
    final state = _categoryKey.currentState;
    if (state == null) return;

    void trySelect() {
      if (state.isLoading) {
        Future.delayed(const Duration(milliseconds: 200), trySelect);
        return;
      }
      final taskCategory = widget.task.category;
      if (taskCategory.isNotEmpty) {
        final id = state.findCategoryIdByName(taskCategory);
        if (id != null) {
          setState(() => _selectedCategoryId = id);
        }
      }
    }

    trySelect();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitTask() async {
    if (_controller.text.isEmpty) {
      _showError("Введите задание");
      return;
    }
    if (_selectedType == 2 && _selectedWeekDays.isEmpty) {
      _showError("Выберите дни недели");
      return;
    }
    if (_selectedType == 3 && _selectedDays.isEmpty) {
      _showError("Выберите дни");
      return;
    }
    if (_selectedCategoryId == null) {
      _showError("Выберите категорию");
      return;
    }

    final categoryName = _categoryKey.currentState?.getCategoryName(_selectedCategoryId!);
    if (categoryName == null) {
      _showError("Категория не найдена");
      return;
    }

    setState(() => _isSubmitting = true);

    final model = EditTaskUiModel(
      taskId: widget.task.taskId,
      taskType: _selectedType ?? 1,
      filialsId: _selectedFilials,
      task: _controller.text,
      days: _selectedType == 1
          ? null
          : _selectedType == 2
              ? _selectedWeekDays
              : _selectedDays,
      hour: _selectedHour,
      minute: _selectedMinute,
      category: categoryName,
    );

    try {
      await _taskService.updateTaskStatus(model);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showError("Ошибка: $e");
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Редактировать задачу"),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Задача',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),

            CategorySelector(
              key: _categoryKey,
              selectedCategoryId: _selectedCategoryId,
              onChanged: (id) => setState(() => _selectedCategoryId = id),
            ),
            const SizedBox(height: 12),

            TaskTypeSelector(
              selectedType: _selectedType ?? 1,
              onTypeChanged: (value) => setState(() {
                _selectedType = value;
                _selectedWeekDays.clear();
                _selectedDays.clear();
              }),
              selectedWeekDays: _selectedWeekDays,
              onWeekDaysChanged: (days) => setState(() => _selectedWeekDays = days),
              selectedDays: _selectedDays,
              onDaysChanged: (days) => setState(() => _selectedDays = days),
            ),

            _buildTimeSelector(),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: _isSubmitting ? null : _submitTask,
                child: _isSubmitting
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text(
                        "Сохранить изменения",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Время выполнения:",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () {
            setState(() {
              _showTimePicker = !_showTimePicker;
              if (_showTimePicker && _selectedHour == null) {
                _selectedHour = DateTime.now().hour;
                _selectedMinute = DateTime.now().minute;
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _selectedHour != null ? Colors.blue.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _selectedHour != null ? Colors.blue.shade200 : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.access_time,
                  color: _selectedHour != null ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 10),
                Text(
                  _selectedHour != null
                      ? "${_selectedHour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')}"
                      : "Выбрать время (необязательно)",
                  style: TextStyle(
                    fontSize: _selectedHour != null ? 24 : 16,
                    fontWeight: FontWeight.bold,
                    color: _selectedHour != null ? Colors.blue : Colors.grey,
                  ),
                ),
                if (_selectedHour != null) ...[
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _selectedHour = null;
                        _selectedMinute = null;
                        _showTimePicker = false;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 15),
        if (_showTimePicker)
          Container(
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              use24hFormat: true,
              initialDateTime: DateTime(
                2026, 1, 1,
                _selectedHour ?? DateTime.now().hour,
                _selectedMinute ?? DateTime.now().minute,
              ),
              onDateTimeChanged: (value) {
                setState(() {
                  _selectedHour = value.hour;
                  _selectedMinute = value.minute;
                });
              },
            ),
          ),
      ],
    );
  }
}
