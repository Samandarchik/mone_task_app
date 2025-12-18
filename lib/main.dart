import 'package:flutter/material.dart';
import 'package:mone_task_app/admin%20copy/ui/admin_ui.dart';
import 'package:mone_task_app/admin/ui/admin_ui.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/worker/ui/task_worker_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupInit();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const LoginPage(),
    );
  }
}

class SpleshScreen extends StatefulWidget {
  const SpleshScreen({super.key});

  @override
  State<SpleshScreen> createState() => SpleshScreenState();
}

class SpleshScreenState extends State<SpleshScreen> {
  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
  }

  void _loadSavedAccounts() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? role = prefs.getString("role");
    if (role == "admin") {
      context.pushAndRemove(AdminTaskUi());
    } else if (role == "checker") {
      context.pushAndRemove(CheckerHomeUi());
    } else {
      context.pushAndRemove(TaskWorkerUi());
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator.adaptive()),
    );
  }
}
