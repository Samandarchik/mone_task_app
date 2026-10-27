import 'dart:async';
import 'dart:io';

import 'package:mone_task_app/shared/services/windows_update_service.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/video_download_provider.dart';
import 'package:mone_task_app/core/data/local/active_filial.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/deep_link_service.dart';
import 'package:mone_task_app/features/deep_link/deep_link_page.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/home/ui/splash_screen.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    MediaKit.ensureInitialized();
  }
  // Windows'da ochiq turgan ilova yangi release'ni o'tkazib yubormasligi
  // uchun davriy (30 daqiqada) avto-yangilanish tekshiruvi.
  WindowsUpdateService.navigatorKey = navigatorKey;
  WindowsUpdateService.startPeriodicChecks();
  await setupInit();
  await ActiveFilial.load();
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
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB),
            surface: Colors.white,
          ),
          scaffoldBackgroundColor: const Color(0xFFF5F6F8),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF5F6F8),
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            titleTextStyle: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFEDEEF1)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          tabBarTheme: const TabBarThemeData(
            labelColor: Color(0xFF2563EB),
            unselectedLabelColor: Color(0xFF6B7280),
            indicatorColor: Color(0xFF2563EB),
            dividerColor: Colors.transparent,
            labelStyle: TextStyle(fontWeight: FontWeight.w700),
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        routes: {"/login": (context) => LoginPage()},
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        home: SpleshScreen(),
      ),
    );
  }
}
