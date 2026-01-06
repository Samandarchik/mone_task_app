import 'package:flutter/material.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class CheckerHomeUi extends StatefulWidget {
  const CheckerHomeUi({super.key});

  @override
  State<CheckerHomeUi> createState() => _CheckerHomeUiState();
}

class _CheckerHomeUiState extends State<CheckerHomeUi> {
  late Future<List<CheckerCheckTaskModel>> tasksFuture;

  @override
  void initState() {
    super.initState();
    tasksFuture = AdminTaskService().fetchTasks();
    getUserFullName();
  }

  String fullName = "";

  void getUserFullName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      fullName = prefs.getString('full_name') ?? '';
    });
  }

  // iOS native video player'da ochish
  Future<void> _openVideoInNativePlayer(String videoPath) async {
    try {
      // Video URL ni to'g'ri formatlash
      String videoUrl = videoPath;
      if (!videoUrl.startsWith('http')) {
        videoUrl = 'https://task.monebakeryuz.uz/$videoPath';
      }

      final Uri videoUri = Uri.parse(videoUrl);

      // iOS'da video'ni native player'da ochish
      if (await canLaunchUrl(videoUri)) {
        await launchUrl(
          videoUri,
          mode: LaunchMode.externalApplication, // Native player'da ochish
        );
      } else {
        // Agar ochilmasa xabar berish
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video ochilmadi'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Video ochishda xatolik: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xatolik: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
              icon: const Icon(Icons.add),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AddAdminTask()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                prefs.remove("access_token");
                prefs.remove("role");
                context.pushAndRemove(LoginPage());
              },
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
        body: FutureBuilder<List<CheckerCheckTaskModel>>(
          future: tasksFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allTasks = snapshot.data as List<CheckerCheckTaskModel>;

            return TabBarView(
              children: [
                buildFilialTasks(allTasks, 1),
                buildFilialTasks(allTasks, 2),
                buildFilialTasks(allTasks, 3),
                buildFilialTasks(allTasks, 4),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget buildFilialTasks(List<CheckerCheckTaskModel> tasks, int filialId) {
    List<CheckerCheckTaskModel> filtered = tasks
        .where((task) => task.filialId == filialId)
        .toList();

    if (filtered.isEmpty) {
      return const Center(child: Text("Ushbu filial uchun task yo'q"));
    }

    return RefreshIndicator(
      onRefresh: () async {
        final newTasks = AdminTaskService().fetchTasks();
        setState(() {
          tasksFuture = newTasks;
        });
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: filtered.length,
        itemBuilder: (_, i) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          color: getStatusColor(filtered[i].taskStatus ?? ""),
          child: InkWell(
            onTap: () {
              print("Tapped on task id: ${filtered[i].id}");
              print("Tapped on task taskId: ${filtered[i].taskId}");
              AdminTaskService().updateTaskStatus(filtered[i].taskId!);
              // Video iOS native player'da ochish

              if (filtered[i].filePath != null &&
                  filtered[i].filePath!.isNotEmpty) {
                _openVideoInNativePlayer(filtered[i].filePath!);
              }
            },

            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Task description
                  Text(
                    filtered[i].description ?? "",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Status va Video info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: getStatusBadgeColor(
                            filtered[i].taskStatus ?? "",
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          getStatusText(filtered[i].taskStatus ?? ""),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      // Video mavjudligi
                      if (filtered[i].filePath != null &&
                          filtered[i].filePath!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.play_circle_filled,
                                size: 16,
                                color: Colors.white,
                              ),
                              SizedBox(width: 4),
                              Text(
                                "Video ko'rish",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String getStatusText(String status) {
    switch (status) {
      case "completed":
        return "Bajarilgan";
      case "checking":
        return "Tekshirilmoqda";
      default:
        return "Yangi";
    }
  }

  Color getStatusBadgeColor(String status) {
    switch (status) {
      case "completed":
        return Colors.green;
      case "checking":
        return Colors.orange;
      default:
        return Colors.red;
    }
  }
}

// Status Color
Color getStatusColor(String status) {
  switch (status) {
    case "completed":
      return Colors.green.shade50;
    case "checking":
      return Colors.orange.shade50;
    default:
      return Colors.red.shade50;
  }
}
