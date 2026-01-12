import 'package:flutter/material.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/checker/ui/player.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/utils/get_color.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Aylana video player
  void _showCircleVideoPlayer(String videoPath) {
    String videoUrl = videoPath;
    if (!videoUrl.startsWith('http')) {
      videoUrl = '${AppUrls.baseUrl}/$videoPath';
    }

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => CircleVideoPlayer(videoUrl: videoUrl),
    );
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
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
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
                          tasksFuture = AdminTaskService().fetchTasks();
                        });
                      },
                      child: const Text('Qayta urinish'),
                    ),
                  ],
                ),
              );
            }

            if (!snapshot.hasData ||
                snapshot.data == null ||
                snapshot.data!.isEmpty) {
              return const Center(child: Text("Hech qanday task topilmadi"));
            }

            final allTasks = snapshot.data!;

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
          color: getStatusColor(filtered[i].status),
          child: InkWell(
            onDoubleTap: () async {
              final bool isDelete = await AdminTaskService().updateTaskStatus(
                filtered[i].taskId,
                3,
              );
              if (isDelete) {
                setState(() {
                  tasksFuture = AdminTaskService().fetchTasks();
                });
              }
            },

            onLongPress: () async {
              final bool isDelete = await AdminTaskService().updateTaskStatus(
                filtered[i].taskId,
                1,
              );
              if (isDelete) {
                setState(() {
                  tasksFuture = AdminTaskService().fetchTasks();
                });
              }
            },
            onTap: () {
              // Aylana video ochish
              if (filtered[i].videoUrl != null &&
                  filtered[i].videoUrl!.isNotEmpty) {
                _showCircleVideoPlayer(filtered[i].videoUrl!);
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    filtered[i].task,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: getStatusColor(filtered[i].status),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          getTypeName(filtered[i].status),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      if (filtered[i].videoUrl != null &&
                          filtered[i].videoUrl!.isNotEmpty)
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
}
