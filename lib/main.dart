import 'package:flutter/material.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/ui/splash_screen.dart';
import 'package:mone_task_app/local_not_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();

  await setupInit();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, home: SpleshScreen());
  }
}
