import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/all_task_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
import 'package:mone_task_app/admin/ui/edit_task_ui.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';

// ==================== Yordamchi (lokal) ====================

const List<String> _weekShort = ['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'];

String _typeLabel(int type) => switch (type) {
  0 || 1 => tr('Har kuni'),
  2 => tr('Har hafta'),
  3 => tr('Har oy'),
  _ => tr('Nomaʼlum'),
};

Color _typeColor(int type) => switch (type) {
  2 => AppColors.success,
  3 => AppColors.warning,
  _ => AppColors.primary,
};

Color _typeSoftColor(int type) => switch (type) {
  2 => AppColors.successSoft,
  3 => AppColors.warningSoft,
  _ => AppColors.primarySoft,
};

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
  late Future<List<TemplateTaskModel>> templatesFuture;
  late Future<List<FilialModel>> categoriesFuture;
  int selectedFilter = -1; // -1: hammasi, 1-3: type bo'yicha

  @override
  void initState() {
    super.initState();
    templatesFuture = TemplateService().fetchTemplates();
    categoriesFuture = TemplateService().fetchFilials();
  }

  void _reloadTemplates() {
    setState(() {
      templatesFuture = TemplateService().fetchTemplates();
    });
  }

  void _reloadFilials() {
    setState(() {
      categoriesFuture = TemplateService().fetchFilials();
    });
  }

  String getFilialNames(List<int> filialIds, List<FilialModel> categories) {
    if (filialIds.isEmpty) return tr('Barcha filiallar');
    final names = {for (var filial in categories) filial.filialId: filial.name};
    return filialIds
        .map((id) => names[id] != null ? displayName(names[id]) : '?')
        .join(', ');
  }

  String formatDays(int type, List<int>? days) {
    if (days == null || days.isEmpty) return "";
    final sorted = List<int>.from(days)..sort();
    if (type == 2) {
      return sorted
          .map((d) => d >= 1 && d <= 7 ? tr(_weekShort[d - 1]) : '$d')
          .join(', ');
    } else if (type == 3) {
      return sorted.join(', ');
    }
    return "";
  }

  Future<void> _openAddTask() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddAdminTask()),
    );
    if (result == true && mounted) _reloadTemplates();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FilialModel>>(
      future: categoriesFuture,
      builder: (context, categorySnapshot) {
        final categories = categorySnapshot.data ?? widget.category ?? [];
        final waiting =
            categorySnapshot.connectionState == ConnectionState.waiting;

        if (categories.isEmpty) {
          Widget body;
          if (waiting) {
            body = const AppLoader();
          } else if (categorySnapshot.hasError) {
            body = AppErrorState(onRetry: _reloadFilials);
          } else {
            body = AppEmptyState(
              icon: Icons.storefront_outlined,
              title: tr('Filiallar topilmadi'),
              message: tr(
                'Vazifa shablonlarini yaratish uchun avval filial qoʻshing.',
              ),
              actionLabel: tr('Filial qoʻshish'),
              onAction: _showAddFilialDialog,
            );
          }
          return Scaffold(
            appBar: AppBar(title: Text(widget.name)),
            body: body,
          );
        }

        return DefaultTabController(
          length: categories.length,
          initialIndex: 0,
          child: Builder(
            builder: (tabContext) => Scaffold(
              appBar: AppBar(
                title: Text(widget.name),
                actions: [
                  PopupMenuButton<String>(
                    tooltip: tr('Filiallar'),
                    icon: Icon(Icons.more_vert_rounded),
                    onSelected: (value) {
                      if (value == 'add') {
                        _showAddFilialDialog();
                      } else if (value == 'edit') {
                        final i = DefaultTabController.of(tabContext).index;
                        if (i >= 0 && i < categories.length) {
                          _showEditFilialDialog(categories[i]);
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'add',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.add_business_outlined),
                          title: Text(tr('Filial qoʻshish')),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text(tr('Filialni tahrirlash')),
                        ),
                      ),
                    ],
                  ),
                ],
                bottom: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: List.generate(
                    categories.length,
                    (index) => GestureDetector(
                      onLongPress: () {
                        _showEditFilialDialog(categories[index]);
                      },
                      child: Tab(text: displayName(categories[index].name)),
                    ),
                  ),
                ),
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: _openAddTask,
                icon: Icon(Icons.add_rounded),
                label: Text(tr('Yangi vazifa')),
              ),
              body: FutureBuilder<List<TemplateTaskModel>>(
                future: templatesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return AppLoader();
                  }
                  if (snapshot.hasError) {
                    return AppErrorState(onRetry: _reloadTemplates);
                  }

                  final allTemplates = snapshot.data ?? [];

                  return TabBarView(
                    children: List.generate(
                      categories.length,
                      (index) => buildFilialTemplates(
                        allTemplates,
                        categories[index].filialId,
                        categories,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ==================== Filial dialoglari ====================

  Future<String?> _askFilialName({
    required String title,
    required String confirmLabel,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? errorText;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void submit() {
              final value = controller.text.trim();
              if (value.isEmpty) {
                setDialogState(() => errorText = tr('Filial nomini kiriting'));
                return;
              }
              Navigator.pop(ctx, value);
            }

            return AlertDialog(
              title: Text(title),
              content: TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('Filial nomi'),
                  errorText: errorText,
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
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _showAddFilialDialog() async {
    final filialName = await _askFilialName(
      title: tr('Yangi filial'),
      confirmLabel: tr('Qoʻshish'),
    );
    if (filialName == null || !mounted) return;

    final bool result = await TemplateService().addFilial(filialName);
    if (!mounted) return;
    if (result) {
      showAppSnack(context, tr('Filial qoʻshildi'), type: SnackType.success);
      _reloadFilials();
    } else {
      showAppSnack(
        context,
        tr('Filialni qoʻshib boʻlmadi'),
        type: SnackType.error,
      );
    }
  }

  void _showEditFilialDialog(FilialModel filial) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                displayName(filial.name),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text(tr('Nomini oʻzgartirish')),
              onTap: () {
                Navigator.pop(ctx);
                _renameFilial(filial);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: AppColors.danger,
              ),
              title: Text(
                tr('Filialni oʻchirish'),
                style: TextStyle(color: AppColors.danger),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteFilial(filial);
              },
            ),
            SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _renameFilial(FilialModel filial) async {
    // Tahrirlash uchun serverdagi xom nom qo'yiladi.
    final newName = await _askFilialName(
      title: tr('Filialni tahrirlash'),
      confirmLabel: tr('Saqlash'),
      initial: filial.name,
    );
    if (newName == null || !mounted) return;

    final ok = await TemplateService().updateFilial(filial.filialId, newName);
    if (!mounted) return;
    if (ok) {
      showAppSnack(context, tr('Saqlandi'), type: SnackType.success);
      _reloadFilials();
    } else {
      showAppSnack(context, tr('Saqlab boʻlmadi'), type: SnackType.error);
    }
  }

  Future<void> _deleteFilial(FilialModel filial) async {
    final confirm = await showConfirmDialog(
      context,
      title: tr('Ishonchingiz komilmi?'),
      message:
          '«${displayName(filial.name)}» ${tr('filiali oʻchiriladi. Bu amalni qaytarib boʻlmaydi.')}',
      confirmLabel: tr('Ha, oʻchirish'),
      destructive: true,
    );
    if (!confirm || !mounted) return;

    final ok = await TemplateService().deleteFilial(filial.filialId);
    if (!mounted) return;
    if (ok) {
      showAppSnack(context, tr('Filial oʻchirildi'), type: SnackType.success);
    } else {
      showAppSnack(
        context,
        tr('Filialni oʻchirib boʻlmadi'),
        type: SnackType.error,
      );
    }
    _reloadFilials();
  }

  // ==================== Ro'yxat ====================

  Widget _buildFilterBar(int total) {
    final filters = <(int, String)>[
      (-1, tr('Barchasi')),
      (1, tr('Har kuni')),
      (2, tr('Har hafta')),
      (3, tr('Har oy')),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (value, label) in filters)
                  Padding(
                    padding: EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: selectedFilter == value,
                      onSelected: (_) => setState(() => selectedFilter = value),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            '$total ${tr('ta vazifa')} · ${tr('tartibni oʻzgartirish uchun ushlab torting')}',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget buildFilialTemplates(
    List<TemplateTaskModel> templates,
    int filialId,
    List<FilialModel> categories,
  ) {
    // Filial bo'yicha filterlash
    List<TemplateTaskModel> filtered = templates.where((template) {
      // Agar filialIds bo'sh bo'lsa, barcha filiallarga tegishli
      if (template.filialIds.isEmpty) return true;
      // Agar filialIds ichida shu filial bo'lsa
      return template.filialIds.contains(filialId);
    }).toList();

    // Type bo'yicha filterlash
    if (selectedFilter != -1) {
      filtered = filtered
          .where(
            (t) =>
                t.type == selectedFilter ||
                (selectedFilter == 1 && t.type == 0),
          )
          .toList();
    }

    Future<void> onRefresh() async {
      final newTemplates = TemplateService().fetchTemplates();
      setState(() {
        templatesFuture = newTemplates;
      });
      await newTemplates;
    }

    if (filtered.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _buildFilterBar(0),
              SizedBox(
                height: math.max(constraints.maxHeight - 160, 320),
                child: AppEmptyState(
                  icon: Icons.checklist_rounded,
                  title: tr('Bu filial uchun vazifalar yoʻq'),
                  message: selectedFilter == -1
                      ? tr(
                          'Yangi vazifa qoʻshing — u har kuni xodimlar roʻyxatida paydo boʻladi.',
                        )
                      : tr(
                          'Bu turdagi vazifa topilmadi. Boshqa filtrni tanlang.',
                        ),
                  actionLabel: tr('Vazifa qoʻshish'),
                  onAction: _openAddTask,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 720),
          child: ReorderableListView.builder(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 96),
            buildDefaultDragHandles: false,
            header: _buildFilterBar(filtered.length),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final template = filtered[index];
              return Padding(
                key: Key('template_${template.templateId}'),
                padding: EdgeInsets.only(bottom: 10),
                child: _buildTemplateCard(
                  template,
                  index,
                  filialId,
                  categories,
                ),
              );
            },
            onReorder: (oldIndex, newIndex) async {
              // MUHIM: oldIndex va newIndex bu list indekslari (0-dan boshlanadi)
              // Lekin backend orderIndex kutadi (1-dan boshlanadi)
              // ReorderableListView pastga surilganda newIndex ni element
              // olib tashlanishidan oldingi pozitsiya bo'yicha beradi — 1 ayiramiz.
              if (newIndex > oldIndex) newIndex -= 1;
              if (newIndex == oldIndex) return;
              final oldOrderIndex = filtered[oldIndex].orderIndex;
              final newOrderIndex =
                  filtered[newIndex.clamp(0, filtered.length - 1)].orderIndex;

              // Backend ga yuborish
              final success = await TemplateService().updateTaskReorder(
                oldOrderIndex,
                newOrderIndex,
              );

              if (!mounted) return;
              if (success) {
                _reloadTemplates();
              } else {
                showAppSnack(
                  context,
                  tr('Tartibni oʻzgartirib boʻlmadi'),
                  type: SnackType.error,
                );
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTemplateCard(
    TemplateTaskModel template,
    int index,
    int currentFilialId,
    List<FilialModel> categories,
  ) {
    final days = formatDays(template.type, template.days);
    final typeText = days.isEmpty
        ? _typeLabel(template.type)
        : '${_typeLabel(template.type)} · $days';
    final time = template.notificationTime;
    final hasTime =
        time != null &&
        time.contains(':') &&
        !time.contains('null') &&
        time.trim().isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EditTaskUi(
                task: TaskModel(
                  taskId: template.templateId,
                  task: template.task,
                  category: template.category,
                  type: template.type,
                  filialId: currentFilialId,
                  days: template.days,
                  notificationTime: template.notificationTime,
                  status: 1,
                ),
              ),
            ),
          );

          // Agar tahrirlash bo'lsa, refresh qilish
          if (result == true && mounted) _reloadTemplates();
        },
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trData(template.task),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Pill(
                          icon: Icons.repeat_rounded,
                          text: typeText,
                          color: _typeColor(template.type),
                          background: _typeSoftColor(template.type),
                        ),
                        if (template.category.trim().isNotEmpty)
                          _Pill(
                            icon: Icons.label_outline_rounded,
                            text: displayName(template.category),
                            color: AppColors.textSecondary,
                            background: AppColors.surfaceMuted,
                          ),
                        if (hasTime)
                          _Pill(
                            icon: Icons.schedule_rounded,
                            text: time,
                            color: AppColors.textSecondary,
                            background: AppColors.surfaceMuted,
                          ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.storefront_outlined,
                            size: 15,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            getFilialNames(template.filialIds, categories),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ReorderableDragStartListener(
                index: index,
                child: Tooltip(
                  message: tr('Tartibni oʻzgartirish'),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.text,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
