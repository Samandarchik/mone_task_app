import 'package:flutter/material.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';

/// Vazifa turi: 1 — har kuni, 2 — har hafta (hafta kunlari), 3 — har oy (sanalar).
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

  static const List<String> _weekShort = [
    'Du',
    'Se',
    'Ch',
    'Pa',
    'Ju',
    'Sh',
    'Ya',
  ];

  @override
  Widget build(BuildContext context) {
    final type = (selectedType >= 1 && selectedType <= 3) ? selectedType : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(tr('Takrorlanishi')),
        SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 1, label: _segLabel(tr('Har kuni'))),
              ButtonSegment(value: 2, label: _segLabel(tr('Har hafta'))),
              ButtonSegment(value: 3, label: _segLabel(tr('Har oy'))),
            ],
            selected: {type},
            onSelectionChanged: (s) {
              if (s.isNotEmpty && s.first != type) onTypeChanged(s.first);
            },
          ),
        ),
        if (type == 2) ...[
          SizedBox(height: AppSpacing.lg),
          _buildWeekDaySelector(context),
        ],
        if (type == 3) ...[
          SizedBox(height: AppSpacing.lg),
          _buildMonthDaySelector(context),
        ],
      ],
    );
  }

  Widget _segLabel(String text) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);

  Widget _buildWeekDaySelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(tr('Hafta kunlari')),
        SizedBox(height: AppSpacing.sm),
        Row(
          children: List.generate(7, (i) {
            final id = i + 1;
            final selected = selectedWeekDays.contains(id);
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 6 ? 0 : 6),
                child: _DayToggle(
                  label: tr(_weekShort[i]),
                  selected: selected,
                  onTap: () {
                    final updated = List<int>.from(selectedWeekDays);
                    selected ? updated.remove(id) : updated.add(id);
                    updated.sort();
                    onWeekDaysChanged(updated);
                  },
                ),
              ),
            );
          }),
        ),
        SizedBox(height: AppSpacing.sm),
        _Hint(
          selectedWeekDays.isEmpty
              ? tr('Vazifa bajariladigan kunlarni belgilang')
              : '${tr('Tanlandi')}: ${(List<int>.from(selectedWeekDays)..sort()).map((d) => d >= 1 && d <= 7 ? tr(_weekShort[d - 1]) : '$d').join(', ')}',
        ),
      ],
    );
  }

  Widget _buildMonthDaySelector(BuildContext context) {
    final sorted = List<int>.from(selectedDays)..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(tr('Oyning kunlari')),
        SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 6.0;
            const perRow = 7;
            final size = ((constraints.maxWidth - gap * (perRow - 1)) / perRow)
                .clamp(36.0, 52.0);
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: List.generate(31, (index) {
                final day = index + 1;
                final selected = selectedDays.contains(day);
                return SizedBox(
                  width: size,
                  height: 44,
                  child: _DayToggle(
                    label: '$day',
                    selected: selected,
                    onTap: () {
                      final updated = List<int>.from(selectedDays);
                      selected ? updated.remove(day) : updated.add(day);
                      updated.sort();
                      onDaysChanged(updated);
                    },
                  ),
                );
              }),
            );
          },
        ),
        SizedBox(height: AppSpacing.sm),
        _Hint(
          sorted.isEmpty
              ? tr('Vazifa bajariladigan sanalarni belgilang')
              : '${tr('Tanlandi')}: ${sorted.join(', ')}',
        ),
      ],
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
      ),
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
    );
  }
}
