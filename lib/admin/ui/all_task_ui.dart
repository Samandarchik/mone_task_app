import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/all_task_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
import 'package:mone_task_app/admin/ui/edit_task_ui.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/utils/get_color.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ==================== UI ====================
class TemplateTaskAdminUi extends StatefulWidget {
  const TemplateTaskAdminUi({super.key});

  @override
  State<TemplateTaskAdminUi> createState() => _TemplateTaskAdminUiState();
}

class _TemplateTaskAdminUiState extends State<TemplateTaskAdminUi> {
  late Future<List<TemplateTaskModel>> templatesFuture;
  String fullName = "";
  int selectedFilter = -1; // -1: hammasi, 1-3: type bo'yicha

  @override
  void initState() {
    super.initState();
    templatesFuture = AdminTaskService().fetchTemplates();
    getUserFullName();
  }

  void getUserFullName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      fullName = prefs.getString('full_name') ?? 'Admin';
    });
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
    final names = {1: "Гелион", 2: "Мархабо", 3: "Фреско", 4: "Сибирский"};
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
      length: 4,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(fullName),
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
            PopupMenuButton<int>(
              icon: const Icon(Icons.filter_list),
              onSelected: (value) {
                setState(() {
                  selectedFilter = value;
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: -1, child: Text("Hammasi")),
                const PopupMenuItem(value: 1, child: Text("Kunlik")),
                const PopupMenuItem(value: 2, child: Text("Haftalik")),
                const PopupMenuItem(value: 3, child: Text("Oyning kunlari")),
              ],
            ),
          ],
          bottom: const TabBar(
            padding: EdgeInsets.zero,
            isScrollable: true,
            tabs: [
              Tab(text: "Гелион"),
              Tab(text: "Мархабо"),
              Tab(text: "Фреско"),
              Tab(text: "Сибирский"),
            ],
          ),
        ),
        body: FutureBuilder<List<TemplateTaskModel>>(
          future: templatesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }

            if (snapshot.hasError) {
              return Center(
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
                          templatesFuture = AdminTaskService().fetchTemplates();
                        });
                      },
                      child: const Text('Qayta urinish'),
                    ),
                  ],
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text("Hech qanday shablon topilmadi"));
            }

            final allTemplates = snapshot.data!;

            return TabBarView(
              children: [
                buildFilialTemplates(allTemplates, 1),
                buildFilialTemplates(allTemplates, 2),
                buildFilialTemplates(allTemplates, 3),
                buildFilialTemplates(allTemplates, 4),
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
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          return _buildTemplateCard(filtered[index], index, filialId);
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
        onLongPress: () async {
          final shouldDelete = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('O\'chirish'),
              content: Text(
                'Ushbu shablonni o\'chirmoqchimisiz?\n"${template.task}"',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Bekor qilish'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('O\'chirish'),
                ),
              ],
            ),
          );

          if (shouldDelete == true) {
            final success = await AdminTaskService().deleteTask(
              template.templateId,
            );
            if (success && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Shablon o\'chirildi')),
              );
              setState(() {
                templatesFuture = AdminTaskService().fetchTemplates();
              });
            }
          }
        },
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
                      '#${template.templateId}',
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
