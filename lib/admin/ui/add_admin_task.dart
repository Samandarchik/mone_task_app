import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/add_admin_task.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';

class AddAdminTask extends StatefulWidget {
  const AddAdminTask({super.key});

  @override
  State<AddAdminTask> createState() => _AddAdminTaskState();
}

class _AddAdminTaskState extends State<AddAdminTask> {
  AdminTaskService taskService = AdminTaskService();
  late TextEditingController controller;
  int type = 1;
  int sellectedType = 2;
  List<int> selectedFilials = []; // tanlangan filiallar listi
  List<int> selectedWeekDays = [];
  List<int> selectedFilial = [];
  List<int> selectedDays = []; // type 3 uchun tanlangan kunlar

  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Добавить задачу")),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Задача',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: DropdownButton<int>(
                  value: type,
                  isExpanded: true,
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
                      });
                    }
                  },
                ),
              ),
              if (type == 2)
                Column(
                  children: [
                    const SizedBox(height: 10),
                    const Text("Будни:"),
                    Column(
                      children: week.map((f) {
                        final bool isSelected = selectedWeekDays.contains(
                          f['id'],
                        );

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                f['name'],
                                style: const TextStyle(fontSize: 16),
                              ),
                              CupertinoSwitch(
                                value: isSelected,
                                onChanged: (bool value) {
                                  setState(() {
                                    if (value) {
                                      selectedWeekDays.add(f['id']);
                                    } else {
                                      selectedWeekDays.remove(f['id']);
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),

              if (type == 3)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    const Text(
                      "Выберите дни:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
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
                    Text("Выбранные дни: ${selectedDays.join(', ')}"),
                  ],
                ),

              const SizedBox(height: 20),
              Center(child: const Text("Филиалы:")),
              Column(
                children: filials.map((f) {
                  final bool isSelected = selectedFilials.contains(f['id']);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(f['name'], style: const TextStyle(fontSize: 16)),
                        CupertinoSwitch(
                          value: isSelected,
                          onChanged: (bool value) {
                            setState(() {
                              if (value) {
                                selectedFilials.add(f['id']);
                              } else {
                                selectedFilials.remove(f['id']);
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

              Center(
                child: CupertinoButton.filled(
                  color: Colors.green,
                  onPressed: () {
                    if (controller.text.isNotEmpty &&
                        selectedFilials.isNotEmpty) {
                      AddAdminTaskModel model = AddAdminTaskModel(
                        taskType: type,
                        filialsId: selectedFilials, // list yuboriladi
                        task: controller.text,
                        days: type == 1
                            ? null
                            : type == 2
                            ? selectedWeekDays
                            : selectedDays,
                      );
                      taskService.addTask(model);
                      Navigator.pop(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Пожалуйста, заполните задачу и выберите филиалы.",
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text("Добавить задачу"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> filials = [
  {"id": 1, "name": "Гелион"},
  {"id": 2, "name": "Мархабо"},
  {"id": 3, "name": "Фреско"},
  {"id": 4, "name": "Сибирский"},
];

List<Map<String, dynamic>> types = [
  {"id": 1, "name": "Ежедневная"},
  {"id": 2, "name": "Еженедельная"},
  {"id": 3, "name": "Ежемесячная"},
];

List<Map<String, dynamic>> week = [
  {"id": 1, "name": "Понедельник"},
  {"id": 2, "name": "Вторник"},
  {"id": 3, "name": "Среда"},
  {"id": 4, "name": "Четверг"},
  {"id": 5, "name": "Пятница"},
  {"id": 6, "name": "Суббота"},
  {"id": 7, "name": "Воскресенье"},
];
