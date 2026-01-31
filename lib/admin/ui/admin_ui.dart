import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/ui/admin_s.dart';
import 'package:mone_task_app/admin/ui/all_task_ui.dart';
import 'package:mone_task_app/admin/ui/user_list_page.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/checker/ui/player.dart';

import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:mone_task_app/worker/service/log_out.dart';

class AdminTaskUi extends StatefulWidget {
  const AdminTaskUi({super.key});

  @override
  State<AdminTaskUi> createState() => _AdminTaskUiState();
}

class _AdminTaskUiState extends State<AdminTaskUi> {
  TokenStorage tokenStorage = sl<TokenStorage>();
  late Future<List<CheckerCheckTaskModel>> tasksFuture;

  late Future<List<FilialModel>> filialModel;
  DateTime selectedDate = DateTime.now();
  UserModel? user;

  @override
  void initState() {
    super.initState();
    user = tokenStorage.getUserData();
    tasksFuture = AdminTaskService().fetchTasks(selectedDate);
    filialModel = AdminTaskService().fetchCategories();
  }

  void _showCircleVideoPlayer(String videoPath) async {
    String realUrl = videoPath.startsWith('http')
        ? videoPath
        : '${AppUrls.baseUrl}/$videoPath';

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) =>
          CircleVideoPlayer(videoUrl: realUrl, isLocal: false),
    );
  }

  void _refreshCategories() {
    setState(() {
      filialModel = AdminTaskService().fetchCategories();
    });
  }

  void _refreshTasks() {
    setState(() {
      tasksFuture = AdminTaskService().fetchTasks(selectedDate);
    });
  }

  Future<void> _handleDateSelection() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 6)),
      initialDate: selectedDate,
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
        tasksFuture = AdminTaskService().fetchTasks(selectedDate);
      });
    }
  }

  Future<void> _handleLogout() async {
    await LogOutService().logOut();
    tokenStorage.removeToken();
    tokenStorage.putUserData({});
    context.pushAndRemove(LoginPage());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FilialModel>>(
      future: filialModel,
      builder: (context, categorySnapshot) {
        // Kategoriyalar yuklanayotganida
        if (categorySnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: Text(user?.username ?? "")),
            body: const Center(child: CircularProgressIndicator.adaptive()),
          );
        }

        // Kategoriyalarda xatolik bo'lsa
        if (categorySnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(user?.username ?? "")),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Kategoriyalarni yuklashda xatolik: ${categorySnapshot.error}',
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshCategories,
                    child: const Text('Qayta urinish'),
                  ),
                ],
              ),
            ),
          );
        }

        // Kategoriyalar bo'sh bo'lsa
        if (!categorySnapshot.hasData ||
            categorySnapshot.data == null ||
            categorySnapshot.data!.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(user?.username ?? "")),
            body: const Center(child: Text("Hech qanday filial topilmadi")),
          );
        }

        final categories = categorySnapshot.data!;

        return DefaultTabController(
          length: categories.length,
          initialIndex: 0,
          child: Scaffold(
            appBar: AppBar(
              actions: [
                GestureDetector(
                  onTap: () {
                    context.push(UsersPage(filialModel: categories));
                  },
                  child: Icon(Icons.person),
                ),
                SizedBox(width: 5),
                GestureDetector(
                  onTap: () {
                    context.push(
                      TemplateTaskAdminUi(
                        name: user?.username ?? "",
                        category: categories,
                      ),
                    );
                  },
                  child: const Icon(Icons.menu),
                ),
                SizedBox(width: 5),
                GestureDetector(
                  onTap: _handleDateSelection,
                  child: Text(
                    selectedDate.day == DateTime.now().day
                        ? "Сегодня "
                        : "${selectedDate.day}/${selectedDate.month}  ",
                  ),
                ),
              ],
              title: Text(user?.username ?? ""),
              leading: IconButton(
                icon: const Icon(Icons.logout),
                onPressed: _handleLogout,
              ),
              bottom: TabBar(
                padding: EdgeInsets.zero,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: List.generate(
                  categories.length,
                  (index) => Tab(text: categories[index].name),
                ),
              ),
            ),
            body: FutureBuilder<List<CheckerCheckTaskModel>>(
              future: tasksFuture,
              builder: (context, taskSnapshot) {
                if (taskSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }

                if (taskSnapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text('Xatolik: ${taskSnapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _refreshTasks,
                          child: const Text('Qayta urinish'),
                        ),
                      ],
                    ),
                  );
                }

                if (!taskSnapshot.hasData ||
                    taskSnapshot.data == null ||
                    taskSnapshot.data!.isEmpty) {
                  return const Center(
                    child: Text("Hech qanday task topilmadi"),
                  );
                }

                final allTasks = taskSnapshot.data!;

                return TabBarView(
                  children: categories.map((category) {
                    return AdminTaskListWidget(
                      tasks: allTasks,
                      filialId: category.filialId,
                      selectedDate: selectedDate,
                      onRefresh: _refreshTasks,
                      onShowVideoPlayer: _showCircleVideoPlayer,
                    );
                  }).toList(),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
