import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/all_task_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
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
  final TextEditingController _filialController = TextEditingController();
  late Future<List<TemplateTaskModel>> templatesFuture;
  late Future<List<FilialModel>> categoriesFuture;
  int selectedFilter = -1; // -1: hammasi, 1-3: type bo'yicha

  @override
  void initState() {
    super.initState();
    templatesFuture = AdminTaskService().fetchTemplates();
    categoriesFuture = AdminTaskService().fetchFilials();
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
    if (filialIds.isEmpty) return "Barcha filiallar";
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
        final categories = categorySnapshot.data ?? widget.category ?? [];

        return DefaultTabController(
          length: categories.length + 1,
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
                    if (result == true) {
                      setState(() {
                        templatesFuture = AdminTaskService().fetchTemplates();
                      });
                    }
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
              bottom: TabBar(
                padding: EdgeInsets.zero,
                isScrollable: true,
                tabs: [
                  ...List.generate(
                    categories.length,
                    (index) => GestureDetector(
                      onLongPress: () {
                        _showEditFilialDialog(categories[index]);
                      },
                      child: Tab(text: categories[index].name),
                    ),
                  ),
                  Tab(
                    child: GestureDetector(
                      onTap: () {
                        _showAddFilialDialog();
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
                      const SizedBox.shrink(),
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

                // Empty state
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
                        categories[index].filialId,
                      ),
                    ),
                    const SizedBox.shrink(),
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
        title: const Text("Filial qo'shish"),
        content: TextField(
          controller: _filialController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "Filial nomi",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Bekor qilish"),
          ),
          TextButton(
            onPressed: () async {
              final filialName = _filialController.text.trim();

              if (filialName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Filial nomini kiriting!'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              // Loading ko'rsatish
              Navigator.pop(context);

              try {
                final bool result = await AdminTaskService().addFilial(
                  filialName,
                );

                if (result) {
                  // Yangi filiallarni yuklash
                  setState(() {
                    categoriesFuture = AdminTaskService().fetchFilials();
                  });
                }
              } catch (e) {}
            },
            child: const Text("Qo'shish"),
          ),
        ],
      ),
    );
  }

  void _showEditFilialDialog(FilialModel filial) {
    _filialController.text = filial.name;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Filialni tahrirlash"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _filialController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: "Filial nomi",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Bekor qilish"),
          ),
          TextButton(
            onPressed: () async {
              // O'chirish funksiyasi
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Ishonchingiz komilmi?"),
                  content: Text("${filial.name} ni o'chirmoqchimisiz?"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Yo'q"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text("Ha, o'chirish"),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                Navigator.pop(context);

                await AdminTaskService().deleteFilial(filial.filialId);

                setState(() {
                  categoriesFuture = AdminTaskService().fetchFilials();
                });
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("O'chirish"),
          ),
          TextButton(
            onPressed: () async {
              final newName = _filialController.text.trim();

              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Filial nomini kiriting!'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              Navigator.pop(context);
              await AdminTaskService().updateFilial(filial.filialId, newName);
              setState(() {
                categoriesFuture = AdminTaskService().fetchFilials();
              });
            },
            child: const Text("Saqlash"),
          ),
        ],
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
    return FutureBuilder<List<FilialModel>>(
      future: categoriesFuture,
      builder: (context, categorySnapshot) {
        final categories = categorySnapshot.data ?? widget.category ?? [];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 3,
          color: getTypeColor(template.type),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final result = await Navigator.push(
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

              // Agar tahrirlash bo'lsa, refresh qilish
              if (result == true) {
                setState(() {
                  templatesFuture = AdminTaskService().fetchTemplates();
                });
              }
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
                  _buildInfoRow(
                    Icons.store,
                    getFilialNames(template.filialIds, categories),
                  ),
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
      },
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
