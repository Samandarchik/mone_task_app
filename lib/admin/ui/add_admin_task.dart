import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/add_admin_task.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';

// ---------- CategoryModel ----------
// Agar sizda alrady CategoryModel bo'lsa, bu classni o'chirting.
class CategoryModel {
  final int id;
  final String name;

  CategoryModel({required this.id, required this.name});

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(id: json['categoryId'], name: json['name']);
  }
}

class AddAdminTask extends StatefulWidget {
  const AddAdminTask({super.key});

  @override
  State<AddAdminTask> createState() => _AddAdminTaskState();
}

class _AddAdminTaskState extends State<AddAdminTask> {
  AdminTaskService taskService = AdminTaskService();
  late TextEditingController controller;
  late Future<List<FilialModel>> filialsFuture;

  int type = 1;
  List<int> selectedFilials = [];
  List<int> selectedWeekDays = [];
  List<int> selectedDays = [];

  // --- Category state ---
  List<CategoryModel> categories = [];
  int? selectedCategoryId;
  bool categoriesLoading = true;
  String? categoriesError;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
    filialsFuture = AdminTaskService().fetchCategories();
    _loadCategories();
  }

  // --- Category API calls ---
  Future<void> _loadCategories() async {
    setState(() {
      categoriesLoading = true;
      categoriesError = null;
    });
    try {
      final list = await taskService.fetchCategoriesList();
      setState(() {
        categories = list;
        categoriesLoading = false;
      });
    } catch (e) {
      setState(() {
        categoriesError = e.toString();
        categoriesLoading = false;
      });
    }
  }

  Future<void> _addCategory(String name) async {
    await taskService.addCategory(name);
    await _loadCategories(); // <-- uncomment — list yangilanadi
  }

  Future<void> _deleteCategory(int id) async {
    final success = await taskService.deleteCategory(id);
    if (success) {
      setState(() {
        if (selectedCategoryId == id) {
          selectedCategoryId = null;
        }
      });
      await _loadCategories();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Ошибка при удалении категории. Возможно, к ней привязаны пользователи.",
            ),
          ),
        );
      }
    }
  }

  // --- Dialog: Yangi category qo'shish ---
  Future<void> _showAddCategoryDialog() async {
    // Local controller yaratamiz — class-level `nameController` o'chiring
    final TextEditingController dialogController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Новая категория"),
          content: TextField(
            controller: dialogController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: "Название категории",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Отмена"),
            ),
            TextButton(
              onPressed: () async {
                final name = dialogController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text("Пожалуйста, введите имя.")),
                  );
                  return;
                }
                Navigator.pop(ctx);
                await _addCategory(name);
              },
              child: const Text("Добавить"),
            ),
          ],
        );
      },
    );
  }

  // --- Confirm delete dialog ---
  Future<void> _confirmDeleteCategory(CategoryModel category) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Удалить"),
          content: Text("\"${category.name}\" Вы хотите удалить категорию?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Неверный"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text("Удалить"),
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
        const SnackBar(content: Text("Пожалуйста, введите задание.")),
      );
      return;
    }

    if (selectedFilials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Пожалуйста, выберите филиалы.")),
      );
      return;
    }

    if (type == 2 && selectedWeekDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Пожалуйста, выберите дни недели.")),
      );
      return;
    }

    if (type == 3 && selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Пожалуйста, выберите даты.")),
      );
      return;
    }

    AddAdminTaskModel model = AddAdminTaskModel(
      taskType: type,
      filialsId: selectedFilials,
      task: controller.text,
      days: type == 1
          ? null
          : type == 2
          ? selectedWeekDays
          : selectedDays,
      category: categories[selectedCategoryId ?? 0].name,
    );
    taskService.addTask(model);
    Navigator.pop(context, true);
  }

  DateTime? selectedDate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Добавить задачу")),
      body: FutureBuilder<List<FilialModel>>(
        future: filialsFuture,
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
                      Future.microtask(() {
                        setState(() {
                          filialsFuture = AdminTaskService().fetchCategories();
                        });
                      });
                    },

                    child: const Text('Повторить попытку'),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Ветви не найдены"));
          }

          final filials = snapshot.data!;

          return SingleChildScrollView(
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

                  // ==================== CATEGORY DROPDOWN ====================
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
                          "Ошибка: $categoriesError",
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _loadCategories,
                          child: const Text("Снова"),
                        ),
                      ],
                    )
                  else
                    _buildCategoryDropdown(),

                  const SizedBox(height: 8),

                  // "Yangi category qo'shish" tugmasi
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _showAddCategoryDialog,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text("Добавить новую категорию"),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ==================== END CATEGORY ====================

                  // Tip tanlash
                  const Text(
                    "Тип задачи:",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: type,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
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
                          type = value;
                          selectedWeekDays.clear();
                          selectedDays.clear();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 20),

                  // Hafta kunlari (type == 2)
                  if (type == 2)
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
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    weekDay['name'],
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  CupertinoSwitch(
                                    value: isSelected,
                                    onChanged: (bool value) {
                                      setState(() {
                                        if (value) {
                                          selectedWeekDays.add(weekDay['id']);
                                        } else {
                                          selectedWeekDays.remove(
                                            weekDay['id'],
                                          );
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 20),
                      ],
                    ),

                  // Oyning kunlari (type == 3)
                  if (type == 3)
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

                  // Filiallar tanlash
                  const Text(
                    "Филиалы:",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  ...filials.map((filial) {
                    final bool isSelected = selectedFilials.contains(
                      filial.filialId,
                    );
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              filial.name,
                              style: const TextStyle(fontSize: 16),
                            ),
                            CupertinoSwitch(
                              value: isSelected,
                              onChanged: (bool value) {
                                setState(() {
                                  if (value) {
                                    selectedFilials.add(filial.filialId);
                                  } else {
                                    selectedFilials.remove(filial.filialId);
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),

                  // Vaqt tanlash
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
                      onDateTimeChanged: (DateTime value) {
                        setState(() {
                          selectedDate = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Qo'shish tugmasi
                  Center(
                    child: SizedBox(
                      width: double.infinity,
                      child: CupertinoButton.filled(
                        onPressed: _submitTask,
                        child: const Text(
                          "Добавить задачу",
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
          );
        },
      ),
    );
  }

  // --- Category Dropdown builder ---
  Widget _buildCategoryDropdown() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
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
                        Text(cat.name),
                        // O'chirish ikona — dropdown ichida
                        GestureDetector(
                          onTap: () {
                            // Dropdown yashirish uchun focus bo'shating
                            FocusManager.instance.primaryFocus?.unfocus();
                            // Bir frame delay berib confirm dialog ochish
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
          ),
        ),
      ],
    );
  }
}

// ==================== Service extension ====================
// Sizning AdminTaskService'ga qo'shing shu methodlarni:
//
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
