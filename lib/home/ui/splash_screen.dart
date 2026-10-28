import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/features/deep_link/deep_link_page.dart';
import 'package:mone_task_app/home/service/check_version.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/home/ui/role_home.dart';
import 'package:mone_task_app/main.dart';
import 'package:mone_task_app/shared/services/windows_update_service.dart';
import 'package:mone_task_app/worker/model/user_model.dart';

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
      // Windows avto-yangilanish: yangi release bo'lsa yopib bo'lmaydigan
      // oyna o'zi yuklab o'rnatadi va ilovani qayta ishga tushiradi —
      // navigatsiyani to'xtatamiz. Windows'da telefon do'konlari tekshiruvi
      // (VersionChecker) kerak emas.
      if (Platform.isWindows) {
        if (await WindowsUpdateService.checkForUpdate()) return;
      }
      if (!mounted) return;
      bool needsUpdate =
          !Platform.isWindows && await VersionChecker.checkVersion(context);
      token = await tokenStorage.getToken();
      userModel = tokenStorage.getUserData();

      // Deep link tekshirilishini kutish (race condition oldini olish)
      await MyApp.initialLinkChecked.future;

      if (!needsUpdate && mounted) {
        _loadSavedAccounts();
      }
    });
  }

  void _loadSavedAccounts() {
    // Deep link kutayotgan bo'lsa — to'g'ridan-to'g'ri DeepLinkPage ga o'tish
    final pending = MyApp.pendingDeepLink;
    if (pending != null) {
      MyApp.pendingDeepLink = null;
      context.pushAndRemove(DeepLinkPage(data: pending));
      return;
    }

    if (token == null || userModel == null) {
      context.pushAndRemove(LoginPage());
      return;
    }
    context.pushAndRemove(landingForUser(userModel!));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator.adaptive()),
    );
  }
}
