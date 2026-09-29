import 'package:flutter/material.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/features/deep_link/deep_link_page.dart';
import 'package:mone_task_app/home/service/check_version.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/home/ui/role_home.dart';
import 'package:mone_task_app/main.dart';
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
      bool needsUpdate = await VersionChecker.checkVersion(context);
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: AppRadius.lgAll,
                boxShadow: AppShadows.raised,
              ),
              child: Icon(
                Icons.task_alt_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
            SizedBox(height: AppSpacing.lg),
            Text(
              'MONE TASK',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(height: AppSpacing.md),
            Text(
              tr('Yuklanmoqda...'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
