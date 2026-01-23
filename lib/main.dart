import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ReorderExample());
  }
}

class ReorderExample extends StatefulWidget {
  const ReorderExample({super.key});

  @override
  State<ReorderExample> createState() => _ReorderExampleState();
}

class _ReorderExampleState extends State<ReorderExample> {
  List<String> items = [
    "1 - Element",
    "2 - Element",
    "3 - Element",
    "4 - Element",
    "5 - Element",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Drag & Drop Print Misol")),
      body: ReorderableListView(
        children: [
          for (int i = 0; i < items.length; i++)
            ListTile(
              key: Key(items[i]),
              title: Text(items[i]),
              tileColor: Colors.grey.shade200,
            ),
        ],

        /// ⚡ Element joyi o'zgarganda ishlaydi
        onReorder: (oldIndex, newIndex) {
          setState(() {
            /// Flutter sababli newIndex bir bosqich pastga siljishi mumkin
            if (newIndex > oldIndex) {
              newIndex -= 1;
            }

            /// O'zgargan elementni oldindan olish
            final movedItem = items[oldIndex];

            /// joyini almashtiramiz
            final item = items.removeAt(oldIndex);
            items.insert(newIndex, item);

            /// 🔥 PRINT QILAMIZ (siz so‘ragan formatda)
            int oldPos = oldIndex + 1; // 1-based
            int newPos = newIndex + 1; // 1-based

            print("$oldPos → $newPos ga ko‘chdi ( ${movedItem} )");
          });
        },
      ),
    );
  }
}
