import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/task_constants.dart';

class TaskTypeSelector extends StatelessWidget {
  final int selectedType;
  final ValueChanged<int> onTypeChanged;
  final List<int> selectedWeekDays;
  final ValueChanged<List<int>> onWeekDaysChanged;
  final List<int> selectedDays;
  final ValueChanged<List<int>> onDaysChanged;

  const TaskTypeSelector({
    super.key,
    required this.selectedType,
    required this.onTypeChanged,
    required this.selectedWeekDays,
    required this.onWeekDaysChanged,
    required this.selectedDays,
    required this.onDaysChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Тип задачи:",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: selectedType,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: taskTypes
              .map((e) => DropdownMenuItem<int>(
                    value: e['id'] as int,
                    child: Text(e['name'] as String),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null) onTypeChanged(value);
          },
        ),
        const SizedBox(height: 20),
        if (selectedType == 2) _buildWeekDaySelector(),
        if (selectedType == 3) _buildMonthDaySelector(),
      ],
    );
  }

  Widget _buildWeekDaySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Будни:",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ...weekDays.map((day) {
          final id = day['id'] as int;
          final isSelected = selectedWeekDays.contains(id);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(day['name'] as String, style: const TextStyle(fontSize: 16)),
                  CupertinoSwitch(
                    value: isSelected,
                    onChanged: (value) {
                      final updated = List<int>.from(selectedWeekDays);
                      if (value) {
                        updated.add(id);
                      } else {
                        updated.remove(id);
                      }
                      onWeekDaysChanged(updated);
                    },
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildMonthDaySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Выберите дни:",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(31, (index) {
            final day = index + 1;
            final isSelected = selectedDays.contains(day);
            return FilterChip(
              label: Text(day.toString()),
              selected: isSelected,
              selectedColor: Colors.blue.shade200,
              onSelected: (selected) {
                final updated = List<int>.from(selectedDays);
                if (selected) {
                  updated.add(day);
                } else {
                  updated.remove(day);
                }
                onDaysChanged(updated);
              },
            );
          }),
        ),
        if (selectedDays.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            "Выбранные дни: ${selectedDays.join(', ')}",
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}
