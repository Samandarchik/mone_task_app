import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/all_task_model.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
import 'package:mone_task_app/admin/ui/widgets/template_task_card.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/shared/widgets/reorderable_filial_tabs.dart';
import 'package:mone_task_app/utils/get_color.dart';

// ==================== UI ====================
class TemplateTaskAdminUi extends StatefulWidget {
  final List<FilialModel>? category;
  final String name;
  const TemplateTaskAdminUi({
    super.key,
    required this.name,
    required this.category,
  });

  @override
  State<TemplateTaskAdminUi> createState() => _TemplateTaskAdminUiState();
}

class _TemplateTaskAdminUiState extends State<TemplateTaskAdminUi> {
  final TextEditingController _filialController = TextEditingController();
  late Future<List<TemplateTaskModel>> templatesFuture;
  late Future<List<FilialModel>> categoriesFuture;
  late Future<List<CategoryModel>> taskCategoriesFuture;

  /// Sudrab o'zgartirilgan filiallar tartibi (server javobini kutmasdan)
  List<FilialModel>? _localFilials;

  /// Kartada tahrirlangan (serverga saqlangan) shablonlar — ro'yxatni
  /// qayta yuklamasdan yangi qiymatlarni ko'rsatish uchun.
  final Map<int, TemplateTaskModel> _edited = {};
  int selectedFilter = -1; // -1: hammasi, 1-3: type bo'yicha

  /// Filiallarni boshqarish va tartibni o'zgartirish — faqat super_admin.
  /// «Задачи» ruxsati berilgan foydalanuvchi faqat vazifa qo'shadi,
  /// tahrirlaydi va o'chiradi (o'z filiallari doirasida).
  final bool _isSuperAdmin =
      sl<TokenStorage>().getUserData()?.role == 'super_admin';

  @override
  void initState() {
    super.initState();
    templatesFuture = TemplateService().fetchTemplates();
    categoriesFuture = TemplateService().fetchFilials();
    taskCategoriesFuture = TemplateService().fetchCategoriesList();
  }

  @override
  void dispose() {
    _filialController.dispose();
    super.dispose();
  }

  Color getTypeColor(int type) {
    switch (type) {
      case 0:
        return Colors.blue.shade100;
      case 1:
        return Colors.green.shade100;
      case 2:
        return Colors.orange.shade100;
      case 3:
        return Colors.purple.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  String getFilialNames(List<int> filialIds, List<FilialModel> categories) {
    if (filialIds.isEmpty) return "Все филиалы";
    final names = {for (var filial in categories) filial.filialId: filial.name};
    return filialIds.map((id) => names[id] ?? "?").join(", ");
  }

  String formatDays(int type, List<int>? days) {
    if (days == null || days.isEmpty) return "";

    if (type == 2) {
      // Haftalik - haftaning kunlari
      return days.map((d) => getWeekday(d)).join(", ");
    } else if (type == 3) {
      // Oyning kunlari
      return days.map((d) => d.toString()).join(", ");
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FilialModel>>(
      future: categoriesFuture,
      builder: (context, categorySnapshot) {
        final categories =
            _localFilials ?? categorySnapshot.data ?? widget.category ?? [];

        return DefaultTabController(
          length: categories.length + (_isSuperAdmin ? 1 : 0),
          initialIndex: 0,
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.name),
              actions: [
                IconButton(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AddAdminTask()),
                    );

                    // Agar yangi task qo'shilsa, refresh qilish
                    if (result == true) _reloadTemplates();
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(kTextTabBarHeight),
                child: Builder(
                  builder: (context) => ReorderableFilialTabs(
                    controller: DefaultTabController.of(context),
                    filials: categories,
                    canReorder: _isSuperAdmin,
                    onReorder: (order) => _saveFilialOrder(categories, order),
                    onDoubleTap: _isSuperAdmin ? _showEditFilialDialog : null,
                    trailing: _isSuperAdmin
                        ? IconButton(
                            onPressed: _showAddFilialDialog,
                            icon: const Icon(Icons.add_circle_outline),
                          )
                        : null,
                  ),
                ),
              ),
            ),
            body: FutureBuilder<List<TemplateTaskModel>>(
              future: templatesFuture,
              builder: (context, snapshot) {
                final categoryCount = categories.length;

                // Loading state
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return TabBarView(
                    children: [
                      ...List.generate(
                        categoryCount,
                        (_) => const Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      ),
                      if (_isSuperAdmin) const SizedBox.shrink(),
                    ],
                  );
                }

                // Error state
                if (snapshot.hasError) {
                  return TabBarView(
                    children: [
                      ...List.generate(
                        categoryCount,
                        (_) => Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text('Ошибка: ${snapshot.error}'),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    templatesFuture = TemplateService()
                                        .fetchTemplates();
                                  });
                                },
                                child: const Text('Повторить'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isSuperAdmin) const SizedBox.shrink(),
                    ],
                  );
                }

                // Empty state
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return TabBarView(
                    children: [
                      ...List.generate(
                        categoryCount,
                        (_) => const Center(child: Text("Шаблоны не найдены")),
                      ),
                      if (_isSuperAdmin) const SizedBox.shrink(),
                    ],
                  );
                }

                final allTemplates = snapshot.data!;

                return TabBarView(
                  children: [
                    ...List.generate(
                      categoryCount,
                      (index) => buildFilialTemplates(
                        allTemplates,
                        categories[index].filialId,
                      ),
                    ),
                    if (_isSuperAdmin) const SizedBox.shrink(),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showAddFilialDialog() {
    _filialController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Добавить филиал"),
        content: TextField(
          controller: _filialController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "Название филиала",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Отмена"),
          ),
          TextButton(
            onPressed: () async {
              final filialName = _filialController.text.trim();

              if (filialName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Введите название филиала!'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              // Loading ko'rsatish
              Navigator.pop(context);

              try {
                final bool result = await TemplateService().addFilial(
                  filialName,
                );

                if (result) {
                  // Yangi filiallarni yuklash
                  setState(() {
                    _localFilials = null;
                    categoriesFuture = TemplateService().fetchFilials();
                  });
                }
              } catch (e) {}
            },
            child: const Text("Добавить"),
          ),
        ],
      ),
    );
  }

  /// Tabni sudrab o'zgartirilgan filiallar tartibini serverga saqlaydi
  Future<void> _saveFilialOrder(
    List<FilialModel> previous,
    List<FilialModel> order,
  ) async {
    setState(() => _localFilials = order);
    final ok = await TemplateService().reorderFilials(
      order.map((f) => f.filialId).toList(),
    );
    if (ok || !mounted) return;
    setState(() => _localFilials = previous);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не удалось сохранить порядок')),
    );
  }

  void _showEditFilialDialog(FilialModel filial) {
    _filialController.text = filial.name;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Редактировать филиал"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _filialController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: "Название филиала",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Отмена"),
          ),
          TextButton(
            onPressed: () async {
              // O'chirish funksiyasi
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Вы уверены?"),
                  content: Text("Удалить ${filial.name}?"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Нет"),
                    ),
                    TextButton(
                      onPressed: () {
                        TemplateService().deleteFilial(filial.filialId);
                        Navigator.pop(context, true);
                      },
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text("Да, удалить"),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                Navigator.pop(context);

                await TemplateService().deleteFilial(filial.filialId);

                setState(() {
                  _localFilials = null;
                  categoriesFuture = TemplateService().fetchFilials();
                });
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Удалить"),
          ),
          TextButton(
            onPressed: () async {
              final newName = _filialController.text.trim();

              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Введите название филиала!'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              Navigator.pop(context);
              await TemplateService().updateFilial(filial.filialId, newName);
              setState(() {
                _localFilials = null;
                categoriesFuture = TemplateService().fetchFilials();
              });
            },
            child: const Text("Сохранить"),
          ),
        ],
      ),
    );
  }

  Widget buildFilialTemplates(List<TemplateTaskModel> templates, int filialId) {
    // Filial bo'yicha filterlash
    List<TemplateTaskModel> filtered = templates
        .map((t) => _edited[t.templateId] ?? t)
        .where((template) {
          // Agar filialIds bo'sh bo'lsa, barcha filiallarga tegishli
          if (template.filialIds.isEmpty) return true;
          // Agar filialIds ichida shu filial bo'lsa
          return template.filialIds.contains(filialId);
        })
        .toList();

    // Type bo'yicha filterlash
    if (selectedFilter != -1) {
      filtered = filtered.where((t) => t.type == selectedFilter).toList();
    }

    if (filtered.isEmpty) {
      return const Center(child: Text("Для этого филиала нет шаблонов"));
    }

    return RefreshIndicator(
      onRefresh: () async {
        final newTemplates = TemplateService().fetchTemplates();
        setState(() {
          _edited.clear();
          templatesFuture = newTemplates;
        });
        await newTemplates;
      },
      child: ReorderableListView.builder(
        // Tutqich belgisi yo'q — kartani bosib turib sudraladi
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.all(12),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final template = filtered[index];
          return ReorderableDelayedDragStartListener(
            key: Key('template_${template.templateId}'),
            index: index,
            enabled: _isSuperAdmin,
            child: _buildTemplateCard(template, index + 1),
          );
        },
        onReorder: (oldIndex, newIndex) async {
          if (!_isSuperAdmin) return;
          // MUHIM: oldIndex va newIndex bu list indekslari (0-dan boshlanadi)
          // Lekin backend orderIndex kutadi (1-dan boshlanadi)

          // Eski va yangi pozitsiyalarni olish
          final oldOrderIndex = filtered[oldIndex].orderIndex;
          final newOrderIndex = newIndex >= filtered.length
              ? filtered.last.orderIndex
              : filtered[newIndex].orderIndex;

          print('🔄 Drag: List index $oldIndex → $newIndex');
          print('📍 Order index $oldOrderIndex → $newOrderIndex');

          // Backend ga yuborish
          final success = await TemplateService().updateTaskReorder(
            oldOrderIndex,
            newOrderIndex,
          );

          if (success) {
            print('✅ Reorder muvaffaqiyatli');
            _reloadTemplates();
          } else {
            print('❌ Reorder muvaffaqiyatsiz');
            // Xatolik haqida xabar
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ошибка при изменении порядка'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  Widget _buildTemplateCard(TemplateTaskModel template, int number) {
    return FutureBuilder<List<FilialModel>>(
      future: categoriesFuture,
      builder: (context, filialSnapshot) {
        final filials = filialSnapshot.data ?? widget.category ?? [];
        return FutureBuilder<List<CategoryModel>>(
          future: taskCategoriesFuture,
          builder: (context, categorySnapshot) {
            return TemplateTaskCard(
              template: template,
              filialNames: getFilialNames(template.filialIds, filials),
              categories: categorySnapshot.data ?? const [],
              onSaved: (updated) =>
                  setState(() => _edited[updated.templateId] = updated),
              onDeleted: _reloadTemplates,
              typeColor: getTypeColor,
              number: number,
              onCategoriesChanged: () => setState(() {
                taskCategoriesFuture = TemplateService().fetchCategoriesList();
              }),
            );
          },
        );
      },
    );
  }

  void _reloadTemplates() {
    setState(() {
      _edited.clear();
      templatesFuture = TemplateService().fetchTemplates();
    });
  }
}
