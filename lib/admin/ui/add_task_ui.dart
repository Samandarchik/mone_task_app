import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/admin_task_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/admin_ui.dart';

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
          title: const Text("Worker Tasks"),
          bottom: const TabBar(
            isScrollable: true, // 🔥 Scroll bo‘ladi
            tabs: [
              Tab(text: "Filial 1"),
              Tab(text: "Filial 2"),
              Tab(text: "Filial 3"),
              Tab(text: "Filial 4"),
            ],
          ),
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

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (_, i) => ListTile(title: Text(filtered[i].description)),
    );
  }
}
