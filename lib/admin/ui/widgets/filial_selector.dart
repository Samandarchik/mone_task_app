import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';

class FilialSelector extends StatelessWidget {
  final List<FilialModel> filials;
  final List<int> selectedIds;
  final ValueChanged<List<int>> onChanged;
  final String title;
  final bool required;

  const FilialSelector({
    super.key,
    required this.filials,
    required this.selectedIds,
    required this.onChanged,
    this.title = "Филиалы:",
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              "$title${required ? ' *' : ''}",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (required && selectedIds.isEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Выбрать',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        ...filials.map((filial) {
          final isSelected = selectedIds.contains(filial.filialId);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(filial.name, style: const TextStyle(fontSize: 16)),
                  CupertinoSwitch(
                    value: isSelected,
                    onChanged: (value) {
                      final updated = List<int>.from(selectedIds);
                      if (value) {
                        updated.add(filial.filialId);
                      } else {
                        updated.remove(filial.filialId);
                      }
                      onChanged(updated);
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
