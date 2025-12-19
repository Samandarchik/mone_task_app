import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/admin_task_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
import 'package:mone_task_app/admin/ui/dialog.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminTaskUi extends StatefulWidget {
  const AdminTaskUi({super.key});

  @override
  State<AdminTaskUi> createState() => _AdminTaskUiState();
}

class _AdminTaskUiState extends State<AdminTaskUi> {
  late Future<List<AdminTaskModel>> tasksFuture;

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
          title: const Text("Admin Panel"),
          bottom: const TabBar(
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
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                prefs.remove("access_token");
                prefs.remove("role");
                context.pushAndRemove(LoginPage());
              },
            ),
          ],
        ),

        body: FutureBuilder(
          future: tasksFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allTasks = snapshot.data as List<AdminTaskModel>;

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
  Widget buildFilialTasks(List<AdminTaskModel> tasks, int filialId) {
    List<AdminTaskModel> filtered = tasks
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
        itemCount: filtered.length,
        itemBuilder: (_, i) => InkWell(
          onLongPress: () async {
            final isDelete = await NativeDialog.showDeleteDialog();

            if (isDelete) {
              await AdminTaskService().deleteTask(filtered[i].id);

              setState(() {
                tasksFuture = AdminTaskService().fetchTasks();
              });
            }
          },

          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white, width: 3)),
              color: getStatusColor(filtered[i].taskStatus),
            ),
            child: Text(
              filtered[i].description,
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
List<AdminTaskModel> filterTasksByDate(List<AdminTaskModel> tasks) {
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
