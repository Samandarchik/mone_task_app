import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/admin_task_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
import 'package:mone_task_app/admin/ui/dialog.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/utils/get_color.dart';

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
              Tab(text: "Сибирский"),
              Tab(text: "Мархабо"),
              Tab(text: "Фреско"),
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
                TokenStorage tokenStorage = sl<TokenStorage>();
                tokenStorage.removeToken();
                context.pushAndRemove(LoginPage());
              },
            ),
          ],
        ),

        body: FutureBuilder(
          future: tasksFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator.adaptive());
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
              await AdminTaskService().deleteTask(filtered[i].taskId);

              setState(() {
                tasksFuture = AdminTaskService().fetchTasks();
              });
            }
          },

          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white, width: 3)),
              color: getStatusColor(filtered[i].status),
            ),
            child: Text(filtered[i].task, style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}
