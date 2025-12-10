import 'package:flutter/material.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/worker/ui/task_worker_ui.dart';

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
      debugShowCheckedModeBanner: false,
      home: const AdminHomeUi(),
    );
  }
}
