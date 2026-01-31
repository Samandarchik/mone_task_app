import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/all_task_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
import 'package:mone_task_app/admin/ui/add_fidial_page.dart';
import 'package:mone_task_app/admin/ui/edit_task_ui.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
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
  late Future<List<TemplateTaskModel>> templatesFuture;
  int selectedFilter = -1; // -1: hammasi, 1-3: type bo'yicha

  @override
  void initState() {
    super.initState();
    templatesFuture = AdminTaskService().fetchTemplates();
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

  String getFilialNames(List<int> filialIds) {
    if (filialIds.isEmpty) return "Barcha filiallar";
    final names = {
      for (var filial in widget.category ?? []) filial.filialId: filial.name,
    };
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
    return DefaultTabController(
      length: (widget.category?.length ?? 0) + 1,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.name),
          actions: [
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddAdminTask()),
                );
              },
              icon: const Icon(Icons.add),
            ),
          ],
          bottom: TabBar(
            padding: EdgeInsets.zero,
            isScrollable: true,
            tabs: [
              ...List.generate(
                widget.category?.length ?? 0,
                (index) => GestureDetector(
                  onLongPress: () {
                    print("ontap");
                  },
                  child: Tab(text: widget.category?[index].name ?? ""),
                ),
              ),
              Tab(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AddFilialPage(
                          isAdd: true,
                          category: widget.category ?? [],
                        ),
                      ),
                    ).then((result) {
                      if (result == true) {
                        setState(() {
                          templatesFuture = AdminTaskService().fetchTemplates();
                        });
                      }
                    });
                  },
                  child: const Icon(Icons.add_circle_outline),
                ),
              ),
            ],
          ),
        ),
        body: FutureBuilder<List<TemplateTaskModel>>(
          future: templatesFuture,
          builder: (context, snapshot) {
            // Loading yoki error holatida ham TabBarView kerak
            final categoryCount = widget.category?.length ?? 0;

            if (snapshot.connectionState == ConnectionState.waiting) {
              return TabBarView(
                children: [
                  ...List.generate(
                    categoryCount,
                    (_) => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                  ),
                  const SizedBox.shrink(),
                ],
              );
            }

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
                          Text('Xatolik: ${snapshot.error}'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                templatesFuture = AdminTaskService()
                                    .fetchTemplates();
                              });
                            },
                            child: const Text('Qayta urinish'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox.shrink(),
                ],
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return TabBarView(
                children: [
                  ...List.generate(
                    categoryCount,
                    (_) => const Center(
                      child: Text("Hech qanday shablon topilmadi"),
                    ),
                  ),
                  const SizedBox.shrink(),
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
                    widget.category![index].filialId,
                  ),
                ),
                const SizedBox.shrink(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget buildFilialTemplates(List<TemplateTaskModel> templates, int filialId) {
    // Filial bo'yicha filterlash
    List<TemplateTaskModel> filtered = templates.where((template) {
      // Agar filialIds bo'sh bo'lsa, barcha filiallarga tegishli
      if (template.filialIds.isEmpty) return true;
      // Agar filialIds ichida shu filial bo'lsa
      return template.filialIds.contains(filialId);
    }).toList();

    // Type bo'yicha filterlash
    if (selectedFilter != -1) {
      filtered = filtered.where((t) => t.type == selectedFilter).toList();
    }

    if (filtered.isEmpty) {
      return const Center(child: Text("Ushbu filial uchun shablon yo'q"));
    }

    return RefreshIndicator(
      onRefresh: () async {
        final newTemplates = AdminTaskService().fetchTemplates();
        setState(() {
          templatesFuture = newTemplates;
        });
        await newTemplates;
      },
      child: ReorderableListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final template = filtered[index];
          return Container(
            key: Key('template_${template.templateId}'),
            child: _buildTemplateCard(template, index, filialId),
          );
        },
        onReorder: (oldIndex, newIndex) async {
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
          final success = await AdminTaskService().updateTaskReorder(
            oldOrderIndex,
            newOrderIndex,
          );

          if (success) {
            print('✅ Reorder muvaffaqiyatli');
            // Qayta yuklash
            setState(() {
              templatesFuture = AdminTaskService().fetchTemplates();
            });
          } else {
            print('❌ Reorder muvaffaqiyatsiz');
            // Xatolik haqida xabar
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tartibni o\'zgartirishda xatolik'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  Widget _buildTemplateCard(
    TemplateTaskModel template,
    int index,
    int currentFilialId,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      color: getTypeColor(template.type),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EditTaskUi(
                task: CheckerCheckTaskModel(
                  taskId: template.templateId,
                  task: template.task,
                  type: template.type,
                  filialId: currentFilialId,
                  days: template.days,
                  notificationTime: template.notificationTime,
                  status: 1,
                ),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '#${template.templateId} [${template.orderIndex}]',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      template.task,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildInfoRow(Icons.category, getTypeName(template.type)),
              const SizedBox(height: 4),
              _buildInfoRow(Icons.store, getFilialNames(template.filialIds)),
              if (template.days != null && template.days!.isNotEmpty) ...[
                const SizedBox(height: 4),
                _buildInfoRow(
                  Icons.calendar_today,
                  formatDays(template.type, template.days),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.black54),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}
