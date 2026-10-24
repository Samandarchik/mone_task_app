import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/all_task_model.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/provider/task_view_sync.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
import 'package:mone_task_app/admin/ui/widgets/template_task_card.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/shared/services/task_prefs_service.dart';
import 'package:mone_task_app/shared/widgets/reorderable_filial_tabs.dart';
import 'package:mone_task_app/shared/widgets/task_reorder_list.dart';
import 'package:mone_task_app/utils/get_color.dart';

// ==================== UI ====================
class TemplateTaskAdminUi extends StatefulWidget {
  final List<FilialModel>? category;
  final String name;

  /// Bosh sahifada bosib turilgan vazifa — ajratib ko'rsatiladi
  final int? highlightTemplateId;

  const TemplateTaskAdminUi({
    super.key,
    required this.name,
    required this.category,
    this.highlightTemplateId,
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

  /// Sudrab o'zgartirilgan tartib — server javobini kutmasdan ko'rsatiladi
  List<TemplateTaskModel>? _reordered;
  int selectedFilter = -1; // -1: hammasi, 1-3: type bo'yicha

  /// Bosh sahifa bilan bir joyda turish (filial + tepadagi vazifa)
  final TaskSyncScope _syncScope = TaskSyncScope();
  List<FilialModel> _categories = const [];
  TabController? _tabs;
  int? _highlightId;

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
    _highlightId = widget.highlightTemplateId;
    if (_highlightId != null) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _highlightId = null);
      });
    }
  }

  /// DefaultTabController o'zgarsa tinglovchini qayta ulaymiz
  void _watchTabs(TabController controller) {
    if (identical(_tabs, controller)) return;
    _tabs?.removeListener(_onTabChanged);
    _tabs = controller..addListener(_onTabChanged);
  }

  TabController _watchTabsOf(BuildContext context) {
    final controller = DefaultTabController.of(context);
    _watchTabs(controller);
    return controller;
  }

  void _onTabChanged() {
    final i = _tabs?.index ?? 0;
    if (i < _categories.length)
      TaskViewSync.selectFilial(_categories[i].filialId);
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTabChanged);
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

        _categories = categories;
        // Bosh sahifadagi filialda ochiladi
        final initialTab = categories.indexWhere(
          (f) => f.filialId == TaskViewSync.filialId,
        );

        return DefaultTabController(
          length: categories.length + (_isSuperAdmin ? 1 : 0),
          initialIndex: initialTab < 0 ? 0 : initialTab,
          // Chiqishda tepadagi vazifani eslab qolamiz — bosh sahifa shu joyga
          // qaytadi
          child: PopScope(
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) _syncScope.capture();
            },
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
                      controller: _watchTabsOf(context),
                      filials: categories,
                      canReorder: _isSuperAdmin,
                      onReorder: (order) => _saveFilialOrder(categories, order),
                      onDoubleTap: _isSuperAdmin ? _showEditFilialDialog : null,
                      trailing: _isSuperAdmin
                          ? IconButton(
                              tooltip: 'Добавить филиал',
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
                          (_) =>
                              const Center(child: Text("Шаблоны не найдены")),
                        ),
                        if (_isSuperAdmin) const SizedBox.shrink(),
                      ],
                    );
                  }

                  final allTemplates = _reordered ?? snapshot.data!;

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

  /// Filialni tahrirlash — ikki marta bosilgan tabning tagida kichik oyna.
  void _showEditFilialDialog(FilialModel filial, BuildContext tabContext) {
    final box = tabContext.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    const width = 280.0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final left = origin.dx.clamp(8.0, screenWidth - width - 8);

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (_) => Stack(
        children: [
          Positioned(
            top: origin.dy + box.size.height + 6,
            left: left,
            width: width,
            child: _FilialEditPopup(
              filial: filial,
              onSave: (name) async {
                await TemplateService().updateFilial(filial.filialId, name);
                _reloadFilials();
              },
              onDelete: () async {
                await TemplateService().deleteFilial(filial.filialId);
                _reloadFilials();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _reloadFilials() {
    if (!mounted) return;
    setState(() {
      _localFilials = null;
      categoriesFuture = TemplateService().fetchFilials();
    });
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

    return _SyncedTemplateList(
      key: ValueKey('templates-$filialId'),
      filialId: filialId,
      templates: filtered,
      scope: _syncScope,
      canReorder: _isSuperAdmin,
      cardBuilder: _buildTemplateCard,
      onRefresh: () async {
        final newTemplates = TemplateService().fetchTemplates();
        setState(() {
          _edited.clear();
          _reordered = null;
          templatesFuture = newTemplates;
        });
        await newTemplates;
      },
      onReorder: (o, n) => _reorderTemplates(
        templates,
        filtered,
        filialId,
        o,
        n > o ? n - 1 : n,
      ),
    );
  }

  /// Bosh sahifadagi kabi: kartani bosib turib sudrash — shaxsiy tartib filial
  /// bo'yicha saqlanadi (super admin uchun umumiy tartib ham shu bo'ladi),
  /// shuning uchun ikkala sahifada ketma-ketlik bir xil qoladi.
  /// Qadalgan vazifa faqat qadalganlar orasida joy almashadi.
  Future<void> _reorderTemplates(
    List<TemplateTaskModel> all,
    List<TemplateTaskModel> visible,
    int filialId,
    int oldIndex,
    int newIndex,
  ) async {
    if (!_isSuperAdmin) return;
    final list = reorderedPinnedAware(
      visible,
      oldIndex,
      newIndex,
      (t) => t.pinned,
    );
    final merged = mergeOrderBy(all, list, (t) => t.templateId);
    setState(() => _reordered = merged);

    final ok = await TaskPrefsService().saveOrder([
      for (final t in merged)
        if (t.filialIds.isEmpty || t.filialIds.contains(filialId)) t.templateId,
    ]);
    if (ok || !mounted) return;
    _reloadTemplates();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ошибка при изменении порядка'),
        backgroundColor: Colors.red,
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
              categories: categorySnapshot.data ?? const [],
              onSaved: (updated) =>
                  setState(() => _edited[updated.templateId] = updated),
              onDeleted: _reloadTemplates,
              typeColor: getTypeColor,
              number: number,
              highlighted: template.templateId == _highlightId,
              onCategoriesChanged: () => setState(() {
                taskCategoriesFuture = TemplateService().fetchCategoriesList();
              }),
              onTemplatesStale: _reloadTemplates,
            );
          },
        );
      },
    );
  }

  void _reloadTemplates() {
    setState(() {
      _edited.clear();
      _reordered = null;
      templatesFuture = TemplateService().fetchTemplates();
    });
  }
}

/// Bitta filialning shablonlari — bosh sahifa bilan bir joyda turadi
/// (tepadagi vazifa [TaskViewSync] orqali almashinadi).
class _SyncedTemplateList extends StatefulWidget {
  final int filialId;
  final List<TemplateTaskModel> templates;
  final TaskSyncScope scope;
  final bool canReorder;
  final Widget Function(TemplateTaskModel template, int number) cardBuilder;
  final Future<void> Function() onRefresh;
  final Future<void> Function(int oldIndex, int newIndex) onReorder;

  const _SyncedTemplateList({
    super.key,
    required this.filialId,
    required this.templates,
    required this.scope,
    required this.canReorder,
    required this.cardBuilder,
    required this.onRefresh,
    required this.onReorder,
  });

  @override
  State<_SyncedTemplateList> createState() => _SyncedTemplateListState();
}

class _SyncedTemplateListState extends State<_SyncedTemplateList>
    with TaskScrollSync {
  @override
  TaskSyncScope? get syncScope => widget.scope;

  @override
  int get syncFilialId => widget.filialId;

  @override
  List<int> get syncTemplateIds =>
      widget.templates.map((t) => t.templateId).toList();

  @override
  Widget build(BuildContext context) {
    final templates = widget.templates;
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: syncScrollListener(
        ReorderableListView.builder(
          scrollController: syncController,
          // Tutqich belgisi yo'q — kartani bosib turib sudraladi
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.all(12),
          itemCount: templates.length,
          itemBuilder: (context, index) {
            final template = templates[index];
            return ReorderableDelayedDragStartListener(
              key: Key('template_${template.templateId}'),
              index: index,
              enabled: widget.canReorder,
              child: KeyedSubtree(
                key: syncKey(template.templateId),
                child: widget.cardBuilder(template, index + 1),
              ),
            );
          },
          onReorder: widget.onReorder,
        ),
      ),
    );
  }
}

/// Tab tagida chiqadigan kichik oyna: nomni o'zgartirish yoki o'chirish.
class _FilialEditPopup extends StatefulWidget {
  final FilialModel filial;
  final Future<void> Function(String name) onSave;
  final Future<void> Function() onDelete;

  const _FilialEditPopup({
    required this.filial,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<_FilialEditPopup> createState() => _FilialEditPopupState();
}

class _FilialEditPopupState extends State<_FilialEditPopup> {
  late final _controller = TextEditingController(text: widget.filial.name)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.filial.name.length,
    );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите название');
      return;
    }
    Navigator.pop(context);
    if (name != widget.filial.name) await widget.onSave(name);
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Вы уверены?"),
        content: Text("Удалить ${widget.filial.name}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Нет"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Да, удалить"),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    Navigator.pop(context);
    await widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Название филиала',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              onSubmitted: (_) => _save(),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                errorText: _error,
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  height: 34,
                  child: TextButton.icon(
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Удалить'),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 34,
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Сохранить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
