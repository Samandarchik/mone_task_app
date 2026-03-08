import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/video_download_provider.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/deep_link_service.dart';
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

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  StreamSubscription? _linkSub;

  /// Ilovada deep link orqali kelgan ma'lumot
  /// Boshqa widgetlar bu qiymatni tekshirishi mumkin
  static DeepLinkData? pendingDeepLink;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // 1. Ilova yopiq holatda link orqali ochilganda
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (_) {}

    // 2. Ilova ochiq holatda link bosilganda
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  void _handleDeepLink(Uri uri) {
    final data = parseDeepLink(uri);
    if (data == null) return;

    debugPrint('🔗 Deep link: $data');

    // Deep link ma'lumotini saqlab qo'yamiz
    pendingDeepLink = data;

    // Agar navigator tayyor bo'lsa — darhol AdminTaskUi ga o'tamiz
    final nav = navigatorKey.currentState;
    if (nav != null) {
      // AdminTasksProvider ga sana o'rnatamiz
      try {
        final ctx = nav.context;
        final provider = Provider.of<AdminTasksProvider>(ctx, listen: false);
        final date = DateTime.tryParse(data.date);
        if (date != null) {
          provider.setSelectedDate(date);
        }
      } catch (_) {}

      // AdminTaskUi sahifasiga o'tish (agar allaqachon u yerda bo'lmasa)
      nav.pushNamedAndRemoveUntil('/admin', (_) => false);
    }
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
          // "/admin": (context) => AdminTaskUi(), // ← AdminTaskUi import qiling
        },
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        home: SpleshScreen(),
      ),
    );
  }
}
