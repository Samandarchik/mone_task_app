import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/edit_task_ui_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
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
  int? sellectedType;
  List<int> selectedFilials = []; // tanlangan filiallar listi
  List<int> selectedWeekDays = [];
  List<int> selectedDays = []; // sellectedType 3 uchun tanlangan kunlar

  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
    controller.text = widget.task.task;
    sellectedType = widget.task.type;
    selectedWeekDays = widget.task.days ?? [];
    selectedDays = widget.task.days ?? [];
    selectedFilials = [widget.task.filialId];
    print(
      "task ${widget.task.task}, sellectedType ${widget.task.type}, filials ${widget.task.filialId}, days ${widget.task.days}",
    );
    setState(() {});
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Задачи редактирования")),
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
                  value: sellectedType,
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
                        sellectedType = value;
                      });
                    }
                  },
                ),
              ),
              if (sellectedType == 2)
                Column(
                  children: [
                    const SizedBox(height: 10),
                    const Text("Будни:"),
                    Column(
                      children: week.map((f) {
                        return CheckboxListTile(
                          title: Text(f['name']),
                          value: selectedWeekDays.contains(f['id']),
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                selectedWeekDays.add(f['id']);
                              } else {
                                selectedWeekDays.remove(f['id']);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              if (sellectedType == 3)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    const Text(
                      "Kunlarni tanlash:",
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
                    Text("Tanlangan kunlar: ${selectedDays.join(', ')}"),
                  ],
                ),

              const SizedBox(height: 20),
              Center(
                child: CupertinoButton.filled(
                  onPressed: () {
                    if (controller.text.isNotEmpty &&
                        selectedFilials.isNotEmpty) {
                      EditTaskUiModel model = EditTaskUiModel(
                        taskId: widget.task.taskId,
                        taskType: sellectedType ?? 1,
                        filialsId: selectedFilials, // list yuboriladi
                        task: controller.text,
                        days: sellectedType == 2
                            ? selectedWeekDays
                            : selectedDays,
                      );
                      taskService.updateTaskStatus(model);
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
                  child: const Text("Задачи редактирования"),
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
