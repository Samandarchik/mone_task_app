import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/ui/admin_ui.dart';
import 'package:mone_task_app/checker/ui/checker_home_ui.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/home/service/check_version.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/worker/ui/task_worker_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SpleshScreen extends StatefulWidget {
  const SpleshScreen({super.key});

  @override
  State<SpleshScreen> createState() => SpleshScreenState();
}

class SpleshScreenState extends State<SpleshScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool needsUpdate = await VersionChecker.checkVersion(context);

      // Agar update kerak bo'lmasa, token tekshiradi
      if (!needsUpdate) {
        _loadSavedAccounts();
      }
    });
  }

  void _loadSavedAccounts() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString("access_token");

    if (token == null) {
      context.pushAndRemove(LoginPage());
      return;
    }
    String? role = prefs.getString("role");

    if (role == "super_admin") {
      context.pushAndRemove(AdminTaskUi());
    } else if (role == "checker") {
      context.pushAndRemove(CheckerHomeUi());
    } else if (role != null) {
      context.pushAndRemove(TaskWorkerUi());
    } else {
      context.pushAndRemove(LoginPage());
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator.adaptive()),
    );
  }
}
