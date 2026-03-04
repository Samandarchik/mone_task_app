import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/get_excel_ui.dart';
import 'package:mone_task_app/admin/ui/all_task_ui.dart';
import 'package:mone_task_app/admin/ui/user_list_page.dart';
import 'package:mone_task_app/admin/ui/video_cache_manager_page.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/worker/model/user_model.dart';

class MyDrawer extends StatelessWidget {
  const MyDrawer({
    super.key,
    required this.categories,
    required this.user,
    required this.onLogout,
  });

  final List<FilialModel> categories;
  final UserModel? user;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // ── Foydalanuvchi ma'lumoti ──────────────────────────────────
            UserAccountsDrawerHeader(
              accountName: Text(user?.username ?? ""),
              accountEmail: Text(user?.role ?? ""),
              currentAccountPicture: const CircleAvatar(
                child: Icon(CupertinoIcons.person, size: 32),
              ),
            ),

            // ── Menyu elementlari ────────────────────────────────────────
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

            // ── Chiziq va chiqish ────────────────────────────────────────
            const Divider(),
            ListTile(
              onTap: () {
                Navigator.pop(context);
                onLogout();
              },
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Выйти", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}
