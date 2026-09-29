import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/add_admin_task.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/widgets/category_selector.dart';
import 'package:mone_task_app/admin/ui/widgets/task_type_selector.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';

class AddAdminTask extends StatefulWidget {
  const AddAdminTask({super.key});

  @override
  State<AddAdminTask> createState() => _AddAdminTaskState();
}

class _AddAdminTaskState extends State<AddAdminTask> {
  final TemplateService _taskService = TemplateService();
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<CategorySelectorState> _categoryKey = GlobalKey();
  late Future<List<FilialModel>> _filialsFuture;

  int _type = 1;
  List<int> _selectedFilials = [];
  List<int> _selectedWeekDays = [];
  List<int> _selectedDays = [];
  int? _selectedCategoryId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _filialsFuture = TemplateService().fetchFilials();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitTask() async {
    if (_controller.text.trim().isEmpty) {
      _showError(tr('Vazifa matnini kiriting'));
      return;
    }
    if (_selectedCategoryId == null) {
      _showError(tr('Kategoriyani tanlang'));
      return;
    }
    if (_type == 2 && _selectedWeekDays.isEmpty) {
      _showError(tr('Hafta kunlarini tanlang'));
      return;
    }
    if (_type == 3 && _selectedDays.isEmpty) {
      _showError(tr('Oyning kunlarini tanlang'));
      return;
    }
    if (_selectedFilials.isEmpty) {
      _showError(tr('Kamida bitta filialni tanlang'));
      return;
    }

    final categoryName = _categoryKey.currentState?.getCategoryName(
      _selectedCategoryId!,
    );
    if (categoryName == null) {
      _showError(tr('Kategoriya topilmadi'));
      return;
    }

    final model = AddAdminTaskModel(
      taskType: _type,
      filialsId: _selectedFilials,
      task: _controller.text,
      days: _type == 1
          ? null
          : _type == 2
          ? _selectedWeekDays
          : _selectedDays,
      category: categoryName,
    );

    setState(() => _isSubmitting = true);
    final ok = await _taskService.addTask(model);
    if (!mounted) return;
    if (ok) {
      showAppSnack(context, tr('Vazifa qoʻshildi'), type: SnackType.success);
      Navigator.pop(context, true);
    } else {
      setState(() => _isSubmitting = false);
      _showError(tr('Vazifani qoʻshib boʻlmadi. Qayta urinib koʻring'));
    }
  }

  void _showError(String message) {
    showAppSnack(context, message, type: SnackType.error);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Yangi vazifa'))),
      body: FutureBuilder<List<FilialModel>>(
        future: _filialsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return AppLoader();
          }
          if (snapshot.hasError) {
            return AppErrorState(
              onRetry: () => setState(() {
                _filialsFuture = TemplateService().fetchFilials();
              }),
            );
          }

          final filials = snapshot.data ?? [];
          if (filials.isEmpty) {
            return AppEmptyState(
              icon: Icons.storefront_outlined,
              title: tr('Filiallar topilmadi'),
              message: tr(
                'Vazifa qoʻshishdan oldin kamida bitta filial yarating.',
              ),
            );
          }

          // SingleChildScrollView — CategorySelector (GlobalKey orqali o'qiladi)
          // pastga aylantirilganda ham o'chib ketmaydi.
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FormCard(
                      children: [
                        TextField(
                          controller: _controller,
                          autofocus: true,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: tr('Vazifa'),
                            hintText: tr('Nima qilish kerakligini yozing'),
                            alignLabelWithHint: true,
                          ),
                          minLines: 2,
                          maxLines: 4,
                        ),
                        SizedBox(height: AppSpacing.lg),
                        CategorySelector(
                          key: _categoryKey,
                          selectedCategoryId: _selectedCategoryId,
                          onChanged: (id) =>
                              setState(() => _selectedCategoryId = id),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.md),
                    _FormCard(
                      children: [
                        TaskTypeSelector(
                          selectedType: _type,
                          onTypeChanged: (value) => setState(() {
                            _type = value;
                            _selectedWeekDays = [];
                            _selectedDays = [];
                          }),
                          selectedWeekDays: _selectedWeekDays,
                          onWeekDaysChanged: (days) =>
                              setState(() => _selectedWeekDays = days),
                          selectedDays: _selectedDays,
                          onDaysChanged: (days) =>
                              setState(() => _selectedDays = days),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.md),
                    _FormCard(
                      children: [
                        _FilialChips(
                          filials: filials,
                          selectedIds: _selectedFilials,
                          onChanged: (ids) =>
                              setState(() => _selectedFilials = ids),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 720),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submitTask,
                  child: _isSubmitting
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(tr('Saqlash')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filiallarni tanlash — chiplar ko'rinishida, "Barchasi" tugmasi bilan.
class _FilialChips extends StatelessWidget {
  const _FilialChips({
    required this.filials,
    required this.selectedIds,
    required this.onChanged,
  });

  final List<FilialModel> filials;
  final List<int> selectedIds;
  final ValueChanged<List<int>> onChanged;

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
            Expanded(
              child: Text(
                tr('Filiallar'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => onChanged(
                allSelected ? [] : filials.map((f) => f.filialId).toList(),
              ),
              child: Text(
                allSelected ? tr('Tozalash') : tr('Barchasini tanlash'),
              ),
            ),
          ],
        ),
        Text(
          selectedIds.isEmpty
              ? tr('Vazifa qaysi filiallarda bajarilishini tanlang')
              : '${tr('Tanlandi')}: ${selectedIds.length} / ${filials.length}',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: filials.map((filial) {
            final selected = selectedIds.contains(filial.filialId);
            return FilterChip(
              label: Text(displayName(filial.name)),
              selected: selected,
              onSelected: (value) {
                final updated = List<int>.from(selectedIds);
                value
                    ? updated.add(filial.filialId)
                    : updated.remove(filial.filialId);
                onChanged(updated);
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
