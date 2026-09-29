import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/video_download_provider.dart';
import 'package:mone_task_app/core/data/local/active_filial.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/deep_link_service.dart';
import 'package:mone_task_app/features/deep_link/deep_link_page.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/home/ui/splash_screen.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && Platform.isWindows) {
    MediaKit.ensureInitialized();
  }
  await setupInit();
  await ActiveFilial.load();
  await AppScriptController.instance.load();
  await AppThemeController.instance.load();
  runApp(MyApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  /// Deep link orqali kelgan ma'lumot — SplashScreen tekshiradi
  static DeepLinkData? pendingDeepLink;

  /// Initial deep link tekshirildi (SplashScreen kutishi uchun)
  static Completer<void> initialLinkChecked = Completer<void>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  StreamSubscription? _linkSub;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    // Har safar yangi Completer (hot restart uchun)
    if (MyApp.initialLinkChecked.isCompleted) {
      MyApp.initialLinkChecked = Completer<void>();
    }
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // 1. Ilova yopiq holatda link orqali ochilganda
    Uri? initialUri;
    try {
      initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        final data = parseDeepLink(initialUri);
        if (data != null) {
          MyApp.pendingDeepLink = data;
        }
      }
    } catch (_) {}

    // SplashScreen ga signal: initial link tekshirildi
    if (!MyApp.initialLinkChecked.isCompleted) {
      MyApp.initialLinkChecked.complete();
    }

    // 2. Ilova ochiq holatda link bosilganda
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      // uriLinkStream initial linkni ham qaytaradi — SplashScreen allaqachon
      // ochgan bo'ladi, ikkinchi marta push qilmaymiz
      if (initialUri != null && uri == initialUri) {
        initialUri = null;
        return;
      }
      final data = parseDeepLink(uri);
      if (data == null) return;

      final nav = navigatorKey.currentState;
      if (nav != null) {
        // Ustiga push qilamiz (remove emas) — ilova holatini buzmaydi
        nav.push(MaterialPageRoute(builder: (_) => DeepLinkPage(data: data)));
      }
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VideoDownloadProvider()),
        ChangeNotifierProvider(create: (_) => AdminTasksProvider()),
      ],
      child: ScriptScope(
        extra: [AppThemeController.instance],
        // Builder — rejim o'zgarganda MaterialApp yangi tema bilan quriladi
        child: Builder(
          builder: (context) => MaterialApp(
            title: 'Mone Task',
            theme: AppTheme.current(),
            // Tizim matnlari (Nusxa olish, Qo'yish, Orqaga ...) — o'zbekcha
            locale: Locale('uz'),
            supportedLocales: [Locale('uz')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            routes: {"/login": (context) => LoginPage()},
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            // Qattiq bosilganda barmoq biroz siljisa ham bosish qabul qilinsin
            // (standart 18 px juda sezgir).
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(
                  gestureSettings: DeviceGestureSettings(touchSlop: 24),
                ),
                child: child!,
              );
            },
            home: SpleshScreen(),
          ),
        ),
      ),
    );
  }
}
