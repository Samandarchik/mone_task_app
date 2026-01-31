import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';

class AddFilialPage extends StatelessWidget {
  final List<FilialModel> category;
  final bool isAdd;
  const AddFilialPage({super.key, required this.category, required this.isAdd});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Filial qo'shish")),
      body: Column(children: []),
    );
  }
}
