import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/video_download_provider.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/deep_link_service.dart';
import 'package:mone_task_app/features/deep_link/deep_link_page.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/home/ui/splash_screen.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupInit();
  runApp(const MyApp());
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
    try {
      final initialUri = await _appLinks.getInitialLink();
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
      final data = parseDeepLink(uri);
      if (data == null) return;

      final nav = navigatorKey.currentState;
      if (nav != null) {
        // Ustiga push qilamiz (remove emas) — ilova holatini buzmaydi
        nav.push(
          MaterialPageRoute(builder: (_) => DeepLinkPage(data: data)),
        );
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
      child: MaterialApp(
        theme: ThemeData(
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
          ),
        ),
        routes: {
          "/login": (context) => LoginPage(),
        },
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        home: SpleshScreen(),
      ),
    );
  }
}
