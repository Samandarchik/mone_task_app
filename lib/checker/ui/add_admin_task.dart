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
  int role = 3;
  int sellectedType = 1;
  List<int> selectedFilials = []; // tanlangan filiallar listi

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
                  value: role,
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
                        role = value;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              const Text("Филиалы:"),
              Column(
                children: filials.map((f) {
                  return CheckboxListTile(
                    title: Text(f['name']),
                    value: selectedFilials.contains(f['id']),
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          selectedFilials.add(f['id']);
                        } else {
                          selectedFilials.remove(f['id']);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              CupertinoButton.filled(
                onPressed: () {
                  if (controller.text.isNotEmpty &&
                      selectedFilials.isNotEmpty) {
                    AddAdminTaskModel model = AddAdminTaskModel(
                      taskType: sellectedType,
                      role: role,
                      filialsId: selectedFilials, // list yuboriladi
                      description: controller.text,
                    );
                    taskService.addTask(model);
                    Navigator.pop(context);
                  } else {
                    // foydalanuvchi hech narsa tanlamagan bo‘lsa
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
            ],
          ),
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> items = [
  {"id": 3, "name": "Мененджер"},
  {"id": 4, "name": "Касса"},
  {"id": 5, "name": "Инспектор"},
];

List<Map<String, dynamic>> filials = [
  {"id": 1, "name": "Гелион"},
  {"id": 2, "name": "Мархабо"},
  {"id": 3, "name": "Фреско"},
  {"id": 4, "name": "Сибирский"},
];

List<Map<String, dynamic>> types = [
  {"id": 1, "name": "Ежедневная", "type": "daily"},
  {"id": 2, "name": "Еженедельная", "type": "weekly"},
  {"id": 3, "name": "Ежемесячная", "type": "monthly"},
];
