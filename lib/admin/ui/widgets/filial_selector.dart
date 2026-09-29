import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';

class FilialSelector extends StatelessWidget {
  final List<FilialModel> filials;
  final List<int> selectedIds;
  final ValueChanged<List<int>> onChanged;

  /// Sarlavha. Berilmasa — "Filiallar".
  final String? title;
  final bool required;

  const FilialSelector({
    super.key,
    required this.filials,
    required this.selectedIds,
    required this.onChanged,
    this.title,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected =
        filials.isNotEmpty &&
        filials.every((f) => selectedIds.contains(f.filialId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                "${title ?? tr('Filiallar')}${required ? ' *' : ''}",
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            SizedBox(width: 8),
            if (required && selectedIds.isEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tr('Tanlang'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger,
                  ),
                ),
              )
            else if (selectedIds.isNotEmpty)
              Text(
                '${selectedIds.length}/${filials.length}',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            Spacer(),
            if (filials.length > 1)
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: Size(0, 36),
                  padding: EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => onChanged(
                  allSelected ? <int>[] : filials.map((f) => f.filialId).toList(),
                ),
                child: Text(
                  allSelected ? tr('Hammasini bekor qilish') : tr('Hammasini tanlash'),
                ),
              ),
          ],
        ),
        SizedBox(height: 8),
        ...filials.map((filial) {
          final isSelected = selectedIds.contains(filial.filialId);
          void toggle(bool value) {
            final updated = List<int>.from(selectedIds);
            if (value) {
              if (!updated.contains(filial.filialId)) {
                updated.add(filial.filialId);
              }
            } else {
              updated.remove(filial.filialId);
            }
            onChanged(updated);
          }

          return Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Material(
              color: isSelected ? AppColors.primarySoft : AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.mdAll,
                side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
              ),
              child: InkWell(
                borderRadius: AppRadius.mdAll,
                onTap: () => toggle(!isSelected),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.storefront_rounded,
                        size: 20,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textTertiary,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          displayName(filial.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      CupertinoSwitch(
                        value: isSelected,
                        activeTrackColor: AppColors.primary,
                        onChanged: toggle,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
