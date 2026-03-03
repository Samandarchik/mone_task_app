import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/circle_video_player.dart';
import 'package:mone_task_app/admin/service/get_excel_ui.dart';
import 'package:mone_task_app/admin/ui/admin_list.dart';
import 'package:mone_task_app/admin/ui/all_task_ui.dart';
import 'package:mone_task_app/admin/ui/user_list_page.dart';
import 'package:mone_task_app/admin/ui/video_cache_manager_page.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:mone_task_app/worker/service/log_out.dart';
import 'package:provider/provider.dart';

class AdminTaskUi extends StatefulWidget {
  const AdminTaskUi({super.key});

  @override
  State<AdminTaskUi> createState() => _AdminTaskUiState();
}

class _AdminTaskUiState extends State<AdminTaskUi> {
  final TokenStorage _tokenStorage = sl<TokenStorage>();
  UserModel? _user;

  @override
  void initState() {
    super.initState();
    _user = _tokenStorage.getUserData();

    // Init providers after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminTasksProvider>().init();
    });
  }

  void _showCircleVideoPlayer(
    List<String> videoPaths,
    int startIndex,
    List<CheckerCheckTaskModel> tasks,
  ) {
    if (videoPaths.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.white30,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: CircleVideoPlayer(
          videoUrls: videoPaths,
          initialIndex: startIndex,
          title: tasks,
        ),
      ),
    );
  }

  Future<void> _handleDateSelection() async {
    final provider = context.read<AdminTasksProvider>();
    final DateTime? picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 6)),
      initialDate: provider.selectedDate,
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      provider.setSelectedDate(picked);
    }
  }

  Future<void> _handleLogout() async {
    await LogOutService().logOut();
    _tokenStorage.removeToken();
    _tokenStorage.putUserData({});
    if (mounted) context.pushAndRemove(LoginPage());
  }

  @override
  Widget build(BuildContext context) {
    final tasksProvider = context.watch<AdminTasksProvider>();

    // ── Loading state ────────────────────────────────────────────────────
    if (tasksProvider.filialsState == LoadingState.loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_user?.username ?? "")),
        body: const Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    // ── Filials error ────────────────────────────────────────────────────
    if (tasksProvider.filialsState == LoadingState.error) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              _tokenStorage.removeToken();
              _tokenStorage.putUserData({});
              context.pushAndRemove(LoginPage());
            },
          ),
          title: Text(_user?.username ?? ""),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                'Kategoriyalarni yuklashda xatolik:\n${tasksProvider.filialsError}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => tasksProvider.fetchFilials(),
                child: const Text('Qayta urinish'),
              ),
            ],
          ),
        ),
      );
    }

    // ── Empty filials ────────────────────────────────────────────────────
    if (tasksProvider.filials.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_user?.username ?? "")),
        body: const Center(child: Text("Hech qanday filial topilmadi")),
      );
    }

    final categories = tasksProvider.filials;

    return DefaultTabController(
      length: categories.length,
      child: Scaffold(
        // ── Drawer ───────────────────────────────────────────────────────
        drawer: _buildDrawer(categories),

        // ── AppBar ───────────────────────────────────────────────────────
        appBar: AppBar(
          title: Text(_user?.username ?? ""),
          actions: [
            GestureDetector(
              onTap: _handleDateSelection,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Text(
                    tasksProvider.selectedDate.day == DateTime.now().day
                        ? "Сегодня"
                        : "${tasksProvider.selectedDate.day}/${tasksProvider.selectedDate.month.toString().padLeft(2, '0')}",
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
            tabs: categories.map((c) => Tab(text: c.name)).toList(),
          ),
        ),
        body: _buildBody(tasksProvider, categories),
      ),
    );
  }

  Widget _buildBody(
    AdminTasksProvider tasksProvider,
    List<FilialModel> categories,
  ) {
    if (tasksProvider.tasksState == LoadingState.loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (tasksProvider.tasksState == LoadingState.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Xatolik: ${tasksProvider.tasksError}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => tasksProvider.fetchTasks(),
              child: const Text('Qayta urinish'),
            ),
          ],
        ),
      );
    }

    if (tasksProvider.tasks.isEmpty) {
      return const Center(child: Text("Hech qanday task topilmadi"));
    }

    return TabBarView(
      children: categories.map((category) {
        return AdminTaskListWidget(
          role: _user?.role ?? "",
          tasks: tasksProvider.tasks,
          filialId: category.filialId,
          selectedDate: tasksProvider.selectedDate,
          onRefresh: () => tasksProvider.fetchTasks(),
          onShowVideoPlayer: _showCircleVideoPlayer,
        );
      }).toList(),
    );
  }

  Widget _buildDrawer(List<FilialModel> categories) {
    return Drawer(
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
                    name: _user?.username ?? "",
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
              title: const Text("Выйти", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}
