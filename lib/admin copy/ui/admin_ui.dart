import 'package:flutter/material.dart';
import 'package:mone_task_app/admin%20copy/model/checker_check_task_model.dart';
import 'package:mone_task_app/admin copy/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
import 'package:mone_task_app/admin/ui/dialog.dart';

class CheckerHomeUi extends StatefulWidget {
  const CheckerHomeUi({super.key});

  @override
  State<CheckerHomeUi> createState() => _CheckerHomeUiState();
}

class _CheckerHomeUiState extends State<CheckerHomeUi> {
  late Future<List<CheckerCheckTaskModel>> tasksFuture;

  @override
  void initState() {
    super.initState();
    tasksFuture = AdminTaskService().fetchTasks();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4, // 🔥 4 ta filial
      initialIndex: 0, // 🔥 Default Filial 1
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Worker Tasks"),
          bottom: const TabBar(
            padding: EdgeInsets.zero,
            isScrollable: true, // 🔥 Scroll bo‘ladi
            tabs: [
              Tab(text: "Гелион"),
              Tab(text: "Мархабо"),
              Tab(text: "Фреско"),
              Tab(text: "Сибирский"),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AddAdminTask()),
              ),
            ),
          ],
        ),

        body: FutureBuilder(
          future: tasksFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allTasks = snapshot.data as List<CheckerCheckTaskModel>;

            return TabBarView(
              children: [
                /// 🔥 Har bir Tab uchun Filial bo‘yicha filter
                buildFilialTasks(allTasks, 1),
                buildFilialTasks(allTasks, 2),
                buildFilialTasks(allTasks, 3),
                buildFilialTasks(allTasks, 4),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 🔥 Har bir filial uchun widget
  Widget buildFilialTasks(List<CheckerCheckTaskModel> tasks, int filialId) {
    List<CheckerCheckTaskModel> filtered = tasks
        .where((task) => task.filialId == filialId)
        .toList();

    filtered = filterTasksByDate(filtered); // daily/weekly filter

    if (filtered.isEmpty) {
      return const Center(child: Text("Ushbu filial uchun task yo'q"));
    }

    return RefreshIndicator(
      onRefresh: () async {
        final newTasks = AdminTaskService().fetchTasks(); // Future qaytadi

        setState(() {
          tasksFuture = newTasks; // faqat state yangilanadi
        });
      },

      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: filtered.length,
        itemBuilder: (_, i) => InkWell(
          onLongPress: () async {
            final isDelete = await NativeDialog.showDeleteDialog();

            if (isDelete) {
              await AdminTaskService().deleteTask(filtered[i].id ?? 0);

              setState(() {
                tasksFuture = AdminTaskService().fetchTasks();
              });
            }
          },

          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white, width: 3)),
              color: getStatusColor(filtered[i].taskStatus ?? ""),
            ),
            child: Text(
              filtered[i].description ?? "",
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
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
List<CheckerCheckTaskModel> filterTasksByDate(
  List<CheckerCheckTaskModel> tasks,
) {
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
