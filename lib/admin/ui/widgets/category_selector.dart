import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';

class CategorySelector extends StatefulWidget {
  final int? selectedCategoryId;
  final ValueChanged<int?> onChanged;

  const CategorySelector({
    super.key,
    required this.selectedCategoryId,
    required this.onChanged,
  });

  @override
  State<CategorySelector> createState() => CategorySelectorState();
}

class CategorySelectorState extends State<CategorySelector> {
  final TemplateService _service = TemplateService();
  List<CategoryModel> categories = [];
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadCategories();
  }

  Future<void> loadCategories() async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      categories = await _service.fetchCategoriesList();
      isLoading = false;
      if (mounted) setState(() {});
    } catch (e) {
      error = e.toString();
      isLoading = false;
      if (mounted) setState(() {});
    }
  }

  /// Nom bo'yicha qidiradi (serverdagi xom nom bilan solishtiriladi).
  int? findCategoryIdByName(String name) {
    final match = categories.where((c) => c.name == name).firstOrNull;
    return match?.id;
  }

  /// Serverdagi xom nomni qaytaradi (API ga yuborish uchun).
  String? getCategoryName(int id) {
    final match = categories.where((c) => c.id == id).firstOrNull;
    return match?.name;
  }

  Future<bool> addCategory(String name) async {
    final ok = await _service.addCategory(name);
    if (ok) await loadCategories();
    return ok;
  }

  Future<bool> deleteCategory(int id) async {
    final success = await _service.deleteCategory(id);
    if (success) {
      if (widget.selectedCategoryId == id) {
        widget.onChanged(null);
      }
      await loadCategories();
    }
    return success;
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        void submit() {
          final value = controller.text.trim();
          if (value.isEmpty) return;
          Navigator.pop(ctx, value);
        }

        return AlertDialog(
          title: Text(tr('Yangi kategoriya')),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr('Kategoriya nomi'),
              hintText: tr('Masalan: Tozalik'),
            ),
            onSubmitted: (_) => submit(),
          ),
          actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(tr('Bekor qilish')),
                  ),
                ),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: submit,
                    child: Text(tr('Qoʻshish')),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final ok = await addCategory(name);
    if (!mounted) return;
    if (ok) {
      showAppSnack(
        context,
        tr('Kategoriya qoʻshildi'),
        type: SnackType.success,
      );
    } else {
      showAppSnack(
        context,
        tr('Kategoriyani qoʻshib boʻlmadi. Qayta urinib koʻring'),
        type: SnackType.error,
      );
    }
  }

  Future<void> _confirmDelete(CategoryModel category) async {
    final ok = await showConfirmDialog(
      context,
      title: tr('Kategoriyani oʻchirish'),
      message:
          '«${displayName(category.name)}» ${tr('kategoriyasi oʻchiriladi. Ishonchingiz komilmi?')}',
      confirmLabel: tr('Ha, oʻchirish'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final success = await deleteCategory(category.id);
    if (!mounted) return;
    if (success) {
      showAppSnack(
        context,
        tr('Kategoriya oʻchirildi'),
        type: SnackType.success,
      );
    } else {
      showAppSnack(
        context,
        tr('Kategoriyani oʻchirib boʻlmaydi — unga maʼlumotlar bogʻlangan'),
        type: SnackType.error,
      );
    }
  }

  void _showManageSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    tr('Kategoriyalar'),
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: categories.isEmpty
                      ? Padding(
                          padding: EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            tr('Hozircha kategoriya yoʻq'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: categories.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, indent: 16),
                          itemBuilder: (_, i) {
                            final cat = categories[i];
                            return ListTile(
                              leading: Icon(
                                Icons.label_outline_rounded,
                                color: AppColors.textSecondary,
                              ),
                              title: Text(
                                displayName(cat.name),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                tooltip: tr('Oʻchirish'),
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppColors.danger,
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _confirmDelete(cat);
                                },
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAddDialog();
                    },
                    icon: Icon(Icons.add_rounded),
                    label: Text(tr('Yangi kategoriya')),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = categories.any((c) => c.id == widget.selectedCategoryId)
        ? widget.selectedCategoryId
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Kategoriya'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        if (isLoading)
          SizedBox(
            height: 52,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          )
        else if (error != null)
          Container(
            padding: EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: AppRadius.mdAll,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.danger,
                  size: 20,
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    tr('Kategoriyalarni yuklab boʻlmadi'),
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
                TextButton(
                  onPressed: loadCategories,
                  child: Text(tr('Qayta urinish')),
                ),
              ],
            ),
          )
        else
          DropdownButtonFormField<int>(
            key: ValueKey('category_$selected'),
            initialValue: selected,
            isExpanded: true,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.label_outline_rounded),
            ),
            hint: Text(
              categories.isEmpty
                  ? tr('Avval kategoriya qoʻshing')
                  : tr('Kategoriyani tanlang'),
            ),
            items: categories
                .map(
                  (cat) => DropdownMenuItem<int>(
                    value: cat.id,
                    child: Text(
                      displayName(cat.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: widget.onChanged,
          ),
        SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            TextButton.icon(
              onPressed: _showAddDialog,
              icon: Icon(Icons.add_rounded, size: 18),
              label: Text(tr('Yangi kategoriya')),
            ),
            if (!isLoading && error == null && categories.isNotEmpty)
              TextButton.icon(
                onPressed: _showManageSheet,
                icon: Icon(Icons.tune_rounded, size: 18),
                label: Text(tr('Kategoriyalarni boshqarish')),
              ),
          ],
        ),
      ],
    );
  }
}
