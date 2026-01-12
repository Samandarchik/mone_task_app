import 'package:flutter/material.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/ui/splash_screen.dart';

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
      home: const SpleshScreen(),
    );
  }
}
