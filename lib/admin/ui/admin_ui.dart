import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/provider/circle_video_player.dart';
import 'package:mone_task_app/admin/service/get_excel_ui.dart';
import 'package:mone_task_app/admin/ui/admin_list.dart';
import 'package:mone_task_app/admin/ui/all_task_ui.dart';
import 'package:mone_task_app/admin/ui/user_list_page.dart';
import 'package:mone_task_app/admin/ui/video_cache_manager_page.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
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
    filialModel = AdminTaskService().fetchFilials();
  }

  /// AdminTaskListWidget dan List<String> va startIndex keladi
  void _showCircleVideoPlayer(
    List<String> videoPaths,
    int startIndex,
    List<CheckerCheckTaskModel> tasks,
  ) {
    if (videoPaths.isEmpty) return;
    showDialog(
      context: context,

      barrierColor: Colors.white30,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: CircleVideoPlayer(
          videoUrls: videoPaths,
          initialIndex: startIndex,
          title: tasks,
        ),
      ),
    );
  }

  void _refreshCategories() {
    setState(() {
      filialModel = AdminTaskService().fetchFilials();
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
    if (mounted) context.pushAndRemove(LoginPage());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FilialModel>>(
      future: filialModel,
      builder: (context, categorySnapshot) {
        if (categorySnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: Text(user?.username ?? "")),
            body: const Center(child: CircularProgressIndicator.adaptive()),
          );
        }

        if (categorySnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () {
                  tokenStorage.removeToken();
                  tokenStorage.putUserData({});
                  context.pushAndRemove(LoginPage());
                },
              ),
              title: Text(user?.username ?? ""),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Kategoriyalarni yuklashda xatolik:\n${categorySnapshot.error}',
                    textAlign: TextAlign.center,
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
            // ─── DRAWER ──────────────────────────────────────────────────
            drawer: Drawer(
              child: SafeArea(
                child: Column(
                  children: [
                    ListTile(
                      onTap: () {
                        Navigator.pop(context);
                        context.push(UsersPage(filialModel: categories));
                      },
                      leading: const Icon(CupertinoIcons.person_2),
                      title: const Text("Все пользователи"),
                    ),
                    ListTile(
                      onTap: () {
                        Navigator.pop(context);
                        context.push(
                          TemplateTaskAdminUi(
                            name: user?.username ?? "",
                            category: categories,
                          ),
                        );
                      },
                      leading: const Icon(CupertinoIcons.list_bullet),
                      title: const Text("Все задачи"),
                    ),
                    ListTile(
                      onTap: () {
                        Navigator.pop(context);
                        context.push(VideoCacheManagerPage());
                      },
                      leading: const Icon(CupertinoIcons.videocam_fill),
                      title: const Text("Кэш видео"),
                    ),
                    ListTile(
                      onTap: () {
                        Navigator.pop(context);
                        context.push(ExcelReportPage(filials: categories));
                      },
                      leading: const Icon(CupertinoIcons.doc_plaintext),
                      title: const Text("Отчеты"),
                    ),
                    const Divider(),
                    ListTile(
                      onTap: _handleLogout,
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text(
                        "Выйти",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ─── APP BAR ─────────────────────────────────────────────────
            appBar: AppBar(
              title: Text(user?.username ?? ""),
              actions: [
                GestureDetector(
                  onTap: _handleDateSelection,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Text(
                        selectedDate.day == DateTime.now().day
                            ? "Сегодня"
                            : "${selectedDate.day}/${selectedDate.month.toString().padLeft(2, '0')}",
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
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

            // ─── BODY ────────────────────────────────────────────────────
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
                        Text(
                          'Xatolik: ${taskSnapshot.error}',
                          textAlign: TextAlign.center,
                        ),
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
                      role: user?.role ?? "",
                      tasks: allTasks,
                      filialId: category.filialId,
                      selectedDate: selectedDate,
                      onRefresh: _refreshTasks,
                      // ← List<String> va int keladi
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
