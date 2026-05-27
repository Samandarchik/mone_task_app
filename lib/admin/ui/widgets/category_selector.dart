import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';

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

  int? findCategoryIdByName(String name) {
    final match = categories.where((c) => c.name == name).firstOrNull;
    return match?.id;
  }

  String? getCategoryName(int id) {
    final match = categories.where((c) => c.id == id).firstOrNull;
    return match?.name;
  }

  Future<void> addCategory(String name) async {
    await _service.addCategory(name);
    await loadCategories();
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

  void _showAddDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Новая категория"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "Название категории",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Отмена"),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await addCategory(name);
            },
            child: const Text("Добавить"),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(CategoryModel category) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Удалить"),
        content: Text('"${category.name}" категорию удалить?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Отмена"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await deleteCategory(category.id);
              if (!success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Категорию нельзя удалить — к ней привязаны данные"),
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Удалить"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Категория:",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (isLoading)
          const Center(child: CircularProgressIndicator.adaptive())
        else if (error != null)
          Row(
            children: [
              Flexible(
                child: Text("Ошибка: $error", style: const TextStyle(color: Colors.red)),
              ),
              TextButton(onPressed: loadCategories, child: const Text("Снова")),
            ],
          )
        else
          DropdownButtonFormField<int>(
            initialValue: widget.selectedCategoryId,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            hint: const Text("Выбрать категорию"),
            items: categories
                .map(
                  (cat) => DropdownMenuItem<int>(
                    value: cat.id,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: Text(cat.name, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _confirmDelete(cat);
                            });
                          },
                          child: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: widget.onChanged,
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _showAddDialog,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text("Добавить новую категорию"),
          ),
        ),
      ],
    );
  }
}
