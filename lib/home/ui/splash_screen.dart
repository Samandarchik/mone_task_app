import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/ui/admin_ui.dart';
import 'package:mone_task_app/checker/ui/checker_home_ui.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/check_version.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:mone_task_app/worker/ui/task_worker_ui.dart';

class SpleshScreen extends StatefulWidget {
  const SpleshScreen({super.key});

  @override
  State<SpleshScreen> createState() => SpleshScreenState();
}

class SpleshScreenState extends State<SpleshScreen> {
  TokenStorage tokenStorage = sl<TokenStorage>();
  UserModel? userModel;
  String? token;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool needsUpdate = await VersionChecker.checkVersion(context);
      token = await tokenStorage.getToken();
      print("token: $token");
      userModel = tokenStorage.getUserData();
      // Agar update kerak bo'lmasa, token tekshiradi
      if (!needsUpdate) {
        _loadSavedAccounts();
      }
    });
  }

  void _loadSavedAccounts() {
    if (token == null || userModel == null) {
      context.pushAndRemove(LoginPage());
      return;
    }
    if (userModel?.role == "super_admin") {
      context.pushAndRemove(AdminTaskUi());
    } else if (userModel?.role == "checker") {
      context.pushAndRemove(CheckerHomeUi());
    } else if (userModel?.role == "worker") {
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
