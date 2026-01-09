import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mone_task_app/camera.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/utils/get_color.dart';
import 'package:mone_task_app/worker/model/task_worker_model.dart';
import 'package:mone_task_app/worker/model/response_task_model.dart';
import 'package:mone_task_app/worker/service/task_worker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class TaskWorkerUi extends StatefulWidget {
  const TaskWorkerUi({super.key});

  @override
  State<TaskWorkerUi> createState() => _TaskWorkerUiState();
}

class _TaskWorkerUiState extends State<TaskWorkerUi> {
  late Future<List<TaskWorkerModel>> tasksFuture;

  @override
  void initState() {
    super.initState();
    tasksFuture = TaskWorkerService().fetchTasks();
  }

  void _refresh() {
    setState(() {
      tasksFuture = TaskWorkerService().fetchTasks();
    });
  }

  /// Video olish dialogini ochish
  Future<void> _showVideoRecorder(TaskWorkerModel task) async {
    final XFile? video = await showDialog<XFile?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => VideoRecorderDialog(maxDuration: 30),
    );

    if (video != null) {
      await _uploadVideo(task, video);
    }
  }

  /// Videoni serverga yuborish
  Future<void> _uploadVideo(TaskWorkerModel task, XFile video) async {
    try {
      // Loading ko'rsatish
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) =>
            const Center(child: CircularProgressIndicator.adaptive()),
      );

      // RequestTaskModel yaratish
      final requestData = RequestTaskModel(
        id: task.id,
        text: "Video orqali bajarildi",
        file: video,
      );

      // Backend ga yuborish
      bool success = await TaskWorkerService().completeTask(requestData);

      Navigator.pop(context); // Loading yopish

      if (success) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Muvaffaqiyatli yuborildi!"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Yuborishda xatolik!"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Loading yopish
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Xatolik: $e"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Задачи"),
        actions: [
          IconButton(
            onPressed: () async {
              SharedPreferences prefs = await SharedPreferences.getInstance();
              prefs.remove("access_token");
              prefs.remove("role");
              context.pushAndRemove(LoginPage());
            },
            icon: Icon(Icons.logout),
          ),
        ],
      ),
      body: FutureBuilder(
        future: tasksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Xatolik: ${snapshot.error}"));
          }

          List<TaskWorkerModel> tasks = snapshot.data ?? [];

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (_, i) => InkWell(
                onTap: () => _showVideoRecorder(tasks[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  margin: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: getStatusColor(tasks[i].taskStatus),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tasks[i].description,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              getTypeName(tasks[i].taskType),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.videocam, color: Colors.grey.shade600),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
