import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';

const _blue = Color(0xFF2563EB);
const _grey = Color(0xFF6B7280);

/// Kategoriyalarni boshqarish: tartibini surib almashtirish, nomini
/// o'zgartirish, o'chirish va yangisini qo'shish.
/// Natija: nomlar o'zgargan bo'lsa — eski nom → yangi nom (bo'lmasa bo'sh).
/// Biror narsa o'zgargan bo'lsa null emas.
Future<Map<String, String>?> showCategoryManager(
  BuildContext context,
  List<CategoryModel> categories,
) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _CategoryManagerDialog(categories: categories),
  );
}

class _CategoryManagerDialog extends StatefulWidget {
  final List<CategoryModel> categories;

  const _CategoryManagerDialog({required this.categories});

  @override
  State<_CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<_CategoryManagerDialog> {
  final TemplateService _service = TemplateService();
  late List<CategoryModel> _items = [...widget.categories];

  /// eski nom → yangi nom
  final Map<String, String> _renamed = {};
  bool _changed = false;
  bool _busy = false;

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _reload() async {
    final fresh = await _service.loadCategories();
    if (mounted) setState(() => _items = fresh);
  }

  Future<String?> _askName({required String title, String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название категории'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == initial) return null;
    return name;
  }

  Future<void> _add() async {
    final name = await _askName(title: 'Новая категория');
    if (name == null) return;
    setState(() => _busy = true);
    final ok = await _service.addCategory(name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return _showError('Такая категория уже есть');
    _changed = true;
    await _reload();
  }

  Future<void> _rename(CategoryModel c) async {
    final name = await _askName(title: 'Переименовать', initial: c.name);
    if (name == null) return;
    setState(() => _busy = true);
    final error = await _service.renameCategory(c.id, name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) return _showError(error);

    // Zanjir: A → B, keyin B → C bo'lsa, A → C
    final origin = _renamed.entries
        .where((e) => e.value == c.name)
        .map((e) => e.key)
        .firstOrNull;
    _renamed[origin ?? c.name] = name;
    _changed = true;
    setState(() {
      final i = _items.indexWhere((e) => e.id == c.id);
      _items[i] = CategoryModel(id: c.id, name: name);
    });
  }

  Future<void> _delete(CategoryModel c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить категорию?'),
        content: Text(c.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    final error = await _service.removeCategory(c.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) return _showError(error);
    _changed = true;
    setState(() => _items.removeWhere((e) => e.id == c.id));
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex == oldIndex) return;
    final previous = [..._items];
    setState(() => _items.insert(newIndex, _items.removeAt(oldIndex)));
    final ok = await _service.reorderCategories(
      _items.map((e) => e.id).toList(),
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _items = previous);
      return _showError('Не удалось сохранить порядок');
    }
    _changed = true;
  }

  void _close() => Navigator.pop(context, _changed ? _renamed : null);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
        title: Row(
          children: [
            const Expanded(child: Text('Категории')),
            if (_busy)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: SizedBox(
          width: 380,
          height: 420,
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: _items.length,
            onReorderItem: _reorder,
            itemBuilder: (_, i) {
              final c = _items[i];
              return ListTile(
                key: ValueKey(c.id),
                contentPadding: const EdgeInsets.only(left: 4, right: 4),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_indicator, color: _grey),
                    ),
                  ),
                ),
                title: Text(c.name, style: const TextStyle(fontSize: 15)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Переименовать',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      color: _blue,
                      onPressed: _busy ? null : () => _rename(c),
                    ),
                    IconButton(
                      tooltip: 'Удалить',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: Colors.red.shade400,
                      onPressed: _busy ? null : () => _delete(c),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Новая'),
          ),
          FilledButton(onPressed: _close, child: const Text('Готово')),
        ],
      ),
    );
  }
}
