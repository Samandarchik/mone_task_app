import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/get_excel_ui.dart';
import 'package:mone_task_app/admin/ui/video_cache_manager_page.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/checker/ui/player.dart';
import 'package:mone_task_app/checker/widgets/task_title.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:mone_task_app/worker/service/log_out.dart';

class CheckerHomeUi extends StatefulWidget {
  const CheckerHomeUi({super.key});

  @override
  State<CheckerHomeUi> createState() => _CheckerHomeUiState();
}

class _CheckerHomeUiState extends State<CheckerHomeUi> {
  late Future<List<CheckerCheckTaskModel>> tasksFuture;
  late Future<List<FilialModel>> categoriesFuture;
  UserModel? user;
  TokenStorage tokenStorage = sl<TokenStorage>();
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    user = tokenStorage.getUserData();
    tasksFuture = AdminTaskService().fetchTasks(selectedDate);
    categoriesFuture = AdminTaskService().fetchFilials();
  }

  void _showCircleVideoPlayer(String videoPath) async {
    String realUrl = videoPath.startsWith('http') ? videoPath : videoPath;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => CircleVideoPlayer(videoUrl: realUrl),
    );
  }

  void _refreshTasks() {
    setState(() {
      tasksFuture = AdminTaskService().fetchTasks(selectedDate);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FilialModel>>(
      future: categoriesFuture,
      builder: (context, categorySnapshot) {
        // Kategoriyalar yuklanayotganida
        if (categorySnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: Text(user?.username ?? "Checker")),
            body: const Center(child: CircularProgressIndicator.adaptive()),
          );
        }

        // Kategoriyalarda xatolik bo'lsa
        if (categorySnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(user?.username ?? "Checker")),
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
                    onPressed: () {
                      setState(() {
                        categoriesFuture = AdminTaskService().fetchFilials();
                      });
                    },
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
            appBar: AppBar(title: Text(user?.username ?? "Checker")),
            body: const Center(child: Text("Hech qanday filial topilmadi")),
          );
        }

        final categories = categorySnapshot.data!;

        return DefaultTabController(
          length: categories.length,
          initialIndex: 0,
          child: Scaffold(
            drawer: Drawer(
              child: SafeArea(
                child: Column(
                  children: [
                    ListTile(
                      onTap: () {
                        context.pop;
                        context.push(VideoCacheManagerPage());
                      },
                      leading: Icon(CupertinoIcons.videocam_fill),
                      title: Text("Все задачи"),
                    ),
                    ListTile(
                      onTap: () {
                        context.pop;
                        context.push(ExcelReportPage(filials: categories));
                      },
                      leading: Icon(CupertinoIcons.doc_plaintext),
                      title: Text("Отчеты"),
                    ),
                    ListTile(
                      onTap: _handleLogout,
                      leading: Icon(Icons.logout, color: Colors.red),
                      title: Text("Выйти", style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ),
            ),
            appBar: AppBar(
              actions: [
                GestureDetector(
                  child: Text(
                    selectedDate.day == DateTime.now().day
                        ? "Сегодня "
                        : "${selectedDate.day}/${selectedDate.month}/${selectedDate.year} ",
                  ),
                  onTap: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 5),
                      ),
                      initialDate: selectedDate,
                      lastDate: DateTime.now(),
                    );

                    if (picked != null) {
                      setState(() {
                        selectedDate = picked;
                        tasksFuture = AdminTaskService().fetchTasks(
                          selectedDate,
                        );
                      });
                    }
                  },
                ),
              ],
              title: Text(user?.username ?? "Checker"),

              bottom: TabBar(
                padding: EdgeInsets.zero,
                isScrollable: true,
                tabs: categories
                    .map((category) => Tab(text: category.name))
                    .toList(),
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
                    return TaskListWidget(
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

  Future<void> _handleLogout() async {
    await LogOutService().logOut();
    tokenStorage.removeToken();
    tokenStorage.putUserData({});
    context.pushAndRemove(LoginPage());
  }
}
