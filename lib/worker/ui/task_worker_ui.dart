import 'package:flutter/material.dart';
import 'package:mone_task_app/worker/model/task_worker_model.dart';
import 'package:mone_task_app/worker/service/task_worker_service.dart';
import 'package:mone_task_app/worker/widgets/dealog.dart';

class TaskWorkerUi extends StatefulWidget {
  const TaskWorkerUi({super.key});

  @override
  State<TaskWorkerUi> createState() => _TaskWorkerUiState();
}

class _TaskWorkerUiState extends State<TaskWorkerUi> {
  late Future<List<TaskWorkerModel>> tasksFuture;

  @override
  void initState() {
    super.initState();
    tasksFuture = TaskWorkerService().fetchTasks();
  }

  void _refresh() {
    setState(() {
      tasksFuture = TaskWorkerService().fetchTasks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Worker Tasks"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: FutureBuilder(
        future: tasksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Xatolik: ${snapshot.error}"));
          }

          List<TaskWorkerModel> tasks = snapshot.data ?? [];

          /// 🔥 TASKLARNI BUGUN UCHUN FILTRLAYMIZ
          tasks = filterTasksByDate(tasks);

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (_, i) => InkWell(
                onTap: () async {
                  final result = await showTaskCompleteDialog(
                    context,
                    tasks[i].id,
                  );

                  if (result != null) {
                    // Backendga yuboramiz
                    bool success = await TaskWorkerService().completeTask(
                      result,
                    );

                    if (success) {
                      _refresh();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Muvaffaqiyatli yuborildi!"),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Yuborishda xatolik!")),
                      );
                    }
                  }
                },

                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 10,
                  ),
                  decoration: BoxDecoration(
                    color: getStatusColor(tasks[i].taskStatus),
                    border: Border.symmetric(
                      horizontal: BorderSide(color: Colors.white),
                    ),
                  ),
                  child: Text(
                    tasks[i].description,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 🔥 STATUS COLOR
Color getStatusColor(String status) {
  switch (status) {
    case "completed":
      return Colors.green.shade100;
    case "checking":
      return Colors.orange.shade100;
    default:
      return Colors.red.shade100;
  }
}

/// 🔥 TASK TYPE BO‘YICHA FILTER
List<TaskWorkerModel> filterTasksByDate(List<TaskWorkerModel> tasks) {
  final now = DateTime.now();

  return tasks.where((task) {
    switch (task.taskType) {
      case "daily":
        return true;

      case "weekly":
        return now.weekday == DateTime.monday;

      case "monthly":
        return now.day == 1;

      default:
        return true;
    }
  }).toList();
}
