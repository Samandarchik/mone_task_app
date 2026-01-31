import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/add_admin_task.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';

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

  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
    filialsFuture = AdminTaskService().fetchCategories();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submitTask() {
    if (controller.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Iltimos, vazifani kiriting")),
      );
      return;
    }

    if (selectedFilials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Iltimos, filiallarni tanlang")),
      );
      return;
    }

    if (type == 2 && selectedWeekDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Iltimos, hafta kunlarini tanlang")),
      );
      return;
    }

    if (type == 3 && selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Iltimos, kunlarni tanlang")),
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
          // Yuklanayotgan payt
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          // Xatolik bo'lsa
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text('Xatolik: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        filialsFuture = AdminTaskService().fetchCategories();
                      });
                    },
                    child: const Text('Qayta urinish'),
                  ),
                ],
              ),
            );
          }

          // Ma'lumot bo'sh bo'lsa
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Hech qanday filial topilmadi"));
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

                  // Tip tanlash
                  const Text(
                    "Тип задачи:",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
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
                    height: 216, // CupertinoDatePicker uchun standart balandlik
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
