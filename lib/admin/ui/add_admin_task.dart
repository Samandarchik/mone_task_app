import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/add_admin_task.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/widgets/category_selector.dart';
import 'package:mone_task_app/admin/ui/widgets/filial_selector.dart';
import 'package:mone_task_app/admin/ui/widgets/task_type_selector.dart';

class AddAdminTask extends StatefulWidget {
  const AddAdminTask({super.key});

  @override
  State<AddAdminTask> createState() => _AddAdminTaskState();
}

class _AddAdminTaskState extends State<AddAdminTask> {
  final TemplateService _taskService = TemplateService();
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<CategorySelectorState> _categoryKey = GlobalKey();
  late Future<List<FilialModel>> _filialsFuture;

  int _type = 1;
  List<int> _selectedFilials = [];
  List<int> _selectedWeekDays = [];
  List<int> _selectedDays = [];
  int? _selectedCategoryId;
  DateTime? _selectedTime;

  @override
  void initState() {
    super.initState();
    _filialsFuture = TemplateService().fetchFilials();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitTask() {
    if (_controller.text.isEmpty) {
      _showError("Пожалуйста, введите задание.");
      return;
    }
    if (_selectedFilials.isEmpty) {
      _showError("Пожалуйста, выберите филиалы.");
      return;
    }
    if (_type == 2 && _selectedWeekDays.isEmpty) {
      _showError("Пожалуйста, выберите дни недели.");
      return;
    }
    if (_type == 3 && _selectedDays.isEmpty) {
      _showError("Пожалуйста, выберите даты.");
      return;
    }
    if (_selectedCategoryId == null) {
      _showError("Пожалуйста, выберите категорию.");
      return;
    }

    final categoryName = _categoryKey.currentState?.getCategoryName(_selectedCategoryId!);
    if (categoryName == null) {
      _showError("Категория не найдена.");
      return;
    }

    final model = AddAdminTaskModel(
      taskType: _type,
      filialsId: _selectedFilials,
      task: _controller.text,
      days: _type == 1 ? null : _type == 2 ? _selectedWeekDays : _selectedDays,
      category: categoryName,
    );
    _taskService.addTask(model);
    Navigator.pop(context, true);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Добавить задачу")),
      body: FutureBuilder<List<FilialModel>>(
        future: _filialsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text('Ошибка: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _filialsFuture = TemplateService().fetchFilials();
                      });
                    },
                    child: const Text('Повторить попытку'),
                  ),
                ],
              ),
            );
          }

          final filials = snapshot.data ?? [];
          if (filials.isEmpty) {
            return const Center(child: Text("Филиалы не найдены"));
          }

          return SingleChildScrollView(
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
                  selectedType: _type,
                  onTypeChanged: (value) => setState(() {
                    _type = value;
                    _selectedWeekDays.clear();
                    _selectedDays.clear();
                  }),
                  selectedWeekDays: _selectedWeekDays,
                  onWeekDaysChanged: (days) => setState(() => _selectedWeekDays = days),
                  selectedDays: _selectedDays,
                  onDaysChanged: (days) => setState(() => _selectedDays = days),
                ),

                FilialSelector(
                  filials: filials,
                  selectedIds: _selectedFilials,
                  onChanged: (ids) => setState(() => _selectedFilials = ids),
                ),
                const SizedBox(height: 20),

                const Text(
                  "Время:",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 216,
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    initialDateTime: DateTime.now(),
                    onDateTimeChanged: (value) => _selectedTime = value,
                  ),
                ),
                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: _submitTask,
                    child: const Text(
                      "Добавить задачу",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}
