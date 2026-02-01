import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/edit_task_ui_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';

class EditTaskUi extends StatefulWidget {
  final CheckerCheckTaskModel task;
  const EditTaskUi({super.key, required this.task});

  @override
  State<EditTaskUi> createState() => _EditTaskUiState();
}

class _EditTaskUiState extends State<EditTaskUi> {
  AdminTaskService taskService = AdminTaskService();
  late TextEditingController controller;

  int? selectedType;
  List<int> selectedFilials = [];
  List<int> selectedWeekDays = [];
  List<int> selectedDays = [];

  // Vaqt uchun
  int? selectedHour;
  int? selectedMinute;
  bool showTimePicker = false;

  // --- Category state ---
  List<CategoryModel> categories = [];
  int? selectedCategoryId;
  bool categoriesLoading = true;
  String? categoriesError;

  @override
  void initState() {
    super.initState();
    print(widget.task.notificationTime);
    controller = TextEditingController(text: widget.task.task);
    selectedType = widget.task.type == 0 ? 1 : widget.task.type;
    selectedFilials = [widget.task.filialId];
    selectedDays = widget.task.days ?? [];
    selectedWeekDays = widget.task.days ?? [];

    // notificationTime parse
    final time = widget.task.notificationTime;
    if (time != null && time != "null:null" && time.contains(':')) {
      final parts = time.split(':');
      selectedHour = int.tryParse(parts[0]);
      selectedMinute = int.tryParse(parts[1]);
    }
    getCategories();
  }

  void getCategories() async {
    final categoriesFuture = await AdminTaskService().loadCategories();
    setState(() {
      categories = categoriesFuture;
      categoriesLoading = false;
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _addCategory(String name) async {
    final success = await taskService.addCategory(name);
    if (success) {
      await AdminTaskService().loadCategories();
      categoriesLoading = false;
    }
  }

  Future<void> _deleteCategory(int id) async {
    final success = await taskService.deleteCategory(id);
    if (success) {
      setState(() {
        if (selectedCategoryId == id) {
          selectedCategoryId = null;
        }
      });
      await AdminTaskService().loadCategories();
      categoriesLoading = false;
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Category o'chirishda xatolik. Unga biriktirilgan userlar bo'lishi mumkin.",
            ),
          ),
        );
      }
    }
  }

  // --- Dialog: Yangi category ---
  Future<void> _showAddCategoryDialog() async {
    final TextEditingController nameController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Yangi Category"),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: "Category nomi",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Bekor"),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text("Iltimos, ism kiriting")),
                  );
                  return;
                }
                Navigator.pop(ctx);
                await _addCategory(name);
              },
              child: const Text("Qo'shish"),
            ),
          ],
        );
      },
    );

    nameController.dispose();
  }

  // --- Confirm delete ---
  Future<void> _confirmDeleteCategory(CategoryModel category) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("O'chirish"),
          content: Text(
            "\"${category.name}\" categoryni o'chirishni istaysizmi?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Bekor"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text("O'chirish"),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteCategory(category.id);
    }
  }

  // --- Submit ---
  void _submitTask() {
    if (controller.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Iltimos, vazifani kiriting")),
      );
      return;
    }

    if (selectedType == 2 && selectedWeekDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Iltimos, hafta kunlarini tanlang")),
      );
      return;
    }

    if (selectedType == 3 && selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Iltimos, kunlarni tanlang")),
      );
      return;
    }
    if (selectedCategoryId == null || categories.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Kategoriyani tanlang")));
      return;
    }
    EditTaskUiModel model = EditTaskUiModel(
      taskId: widget.task.taskId,
      taskType: selectedType ?? 1,
      filialsId: selectedFilials,
      task: controller.text,
      days: selectedType == 1
          ? null
          : selectedType == 2
          ? selectedWeekDays
          : selectedDays,
      hour: selectedHour,
      minute: selectedMinute,
      category: categories[selectedCategoryId ?? 0].name,
      // categoryId model'ga qo'shilgan bo'lishi kerak
      // categoryId: selectedCategoryId,
    );

    taskService.updateTaskStatus(model);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Задачи редактирования")),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vazifa kiritish
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Задача',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 20),

              // ==================== CATEGORY ====================
              const Text(
                "Категория:",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              if (categoriesLoading)
                const Center(child: CircularProgressIndicator.adaptive())
              else if (categoriesError != null)
                Row(
                  children: [
                    Text(
                      "Xatolik: $categoriesError",
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        await AdminTaskService().loadCategories();
                        categoriesLoading = false;
                      },
                      child: const Text("Qayta"),
                    ),
                  ],
                )
              else
                _buildCategoryDropdown(),

              const SizedBox(height: 8),

              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _showAddCategoryDialog,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text("Yangi category qo'shish"),
                ),
              ),
              const SizedBox(height: 12),
              // ==================== END CATEGORY ====================

              // Tip tanlash
              const Text(
                "Тип задачи:",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: selectedType,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: types
                    .map(
                      (e) => DropdownMenuItem<int>(
                        value: e['id'],
                        child: Text(e['name']),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      selectedType = value;
                      selectedWeekDays.clear();
                      selectedDays.clear();
                    });
                  }
                },
              ),
              const SizedBox(height: 20),

              // Hafta kunlari (type == 2)
              if (selectedType == 2)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Будни:",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...week.map((weekDay) {
                      final bool isSelected = selectedWeekDays.contains(
                        weekDay['id'],
                      );
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: CheckboxListTile(
                          title: Text(weekDay['name']),
                          value: isSelected,
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                selectedWeekDays.add(weekDay['id']);
                              } else {
                                selectedWeekDays.remove(weekDay['id']);
                              }
                            });
                          },
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                  ],
                ),

              // Oyning kunlari (type == 3)
              if (selectedType == 3)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Выберите дни:",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(31, (index) {
                        int day = index + 1;
                        bool isSelected = selectedDays.contains(day);
                        return FilterChip(
                          label: Text(day.toString()),
                          selected: isSelected,
                          selectedColor: Colors.blue.shade200,
                          onSelected: (bool selected) {
                            setState(() {
                              if (selected) {
                                selectedDays.add(day);
                              } else {
                                selectedDays.remove(day);
                              }
                            });
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 10),
                    if (selectedDays.isNotEmpty)
                      Text(
                        "Выбранные дни: ${selectedDays.join(', ')}",
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    const SizedBox(height: 20),
                  ],
                ),

              // Vaqt tanlash tugmasi
              const Text(
                "Время выполнения:",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              GestureDetector(
                onTap: () {
                  setState(() {
                    showTimePicker = !showTimePicker;
                    if (showTimePicker && selectedHour == null) {
                      selectedHour = DateTime.now().hour;
                      selectedMinute = DateTime.now().minute;
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: selectedHour != null
                        ? Colors.blue.shade50
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selectedHour != null
                          ? Colors.blue.shade200
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.access_time,
                        color: selectedHour != null ? Colors.blue : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        selectedHour != null
                            ? "${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}"
                            : "Vaqtni tanlash (ixtiyoriy)",
                        style: TextStyle(
                          fontSize: selectedHour != null ? 24 : 16,
                          fontWeight: FontWeight.bold,
                          color: selectedHour != null
                              ? Colors.blue
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (selectedHour != null)
                        IconButton(
                          icon: const Icon(Icons.clear, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              selectedHour = null;
                              selectedMinute = null;
                              showTimePicker = false;
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 15),

              if (showTimePicker)
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
                      2026,
                      1,
                      1,
                      selectedHour ?? DateTime.now().hour,
                      selectedMinute ?? DateTime.now().minute,
                    ),
                    onDateTimeChanged: (DateTime value) {
                      setState(() {
                        selectedHour = value.hour;
                        selectedMinute = value.minute;
                      });
                    },
                  ),
                ),
              const SizedBox(height: 30),

              // Saqlash tugmasi
              Center(
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: _submitTask,
                    child: const Text(
                      "Сохранить изменения",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // --- Category Dropdown ---
  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<int>(
      value: selectedCategoryId,
      isExpanded: true,
      decoration: const InputDecoration(border: OutlineInputBorder()),
      hint: const Text("Выбирать"),
      items: categories
          .map(
            (cat) => DropdownMenuItem<int>(
              value: cat.id,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(cat.name, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _confirmDeleteCategory(cat);
                      });
                    },
                    child: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          selectedCategoryId = value;
        });
      },
    );
  }
}

// Types ma'lumotlari
const List<Map<String, dynamic>> types = [
  {'id': 1, 'name': 'Ежедневно'},
  {'id': 2, 'name': 'Еженедельно'},
  {'id': 3, 'name': 'Ежемесячно'},
];

// Hafta kunlari
const List<Map<String, dynamic>> week = [
  {'id': 1, 'name': 'Понедельник'},
  {'id': 2, 'name': 'Вторник'},
  {'id': 3, 'name': 'Среда'},
  {'id': 4, 'name': 'Четверг'},
  {'id': 5, 'name': 'Пятница'},
  {'id': 6, 'name': 'Суббота'},
  {'id': 7, 'name': 'Воскресенье'},
];
