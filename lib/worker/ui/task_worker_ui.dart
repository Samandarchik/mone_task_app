import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mone_task_app/checker/ui/player.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/utils/get_color.dart';
import 'package:mone_task_app/worker/model/task_worker_model.dart';
import 'package:mone_task_app/worker/model/response_task_model.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:mone_task_app/worker/service/log_out.dart';
import 'package:mone_task_app/worker/service/task_worker_service.dart';
import 'dart:async';

import 'package:mone_task_app/worker/ui/telegram_style_video_recorder.dart';

class TaskWorkerUi extends StatefulWidget {
  const TaskWorkerUi({super.key});

  @override
  State<TaskWorkerUi> createState() => _TaskWorkerUiState();
}

class _TaskWorkerUiState extends State<TaskWorkerUi> {
  late Future<List<TaskWorkerModel>> tasksFuture;
  bool _isRecording = false;
  TokenStorage tokenStorage = sl<TokenStorage>();
  Timer? _recordingTimer;
  UserModel? user;
  @override
  void initState() {
    super.initState();
    tasksFuture = TaskWorkerService().fetchTasks();
    user = tokenStorage.getUserData();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      tasksFuture = TaskWorkerService().fetchTasks();
    });
  }

  /// Video olish dialogini ochish
  Future<void> _showVideoRecorder(TaskWorkerModel task) async {
    setState(() => _isRecording = true);

    final result = await showGeneralDialog(
      context: context,
      barrierDismissible: false, // Yozish paytida dismiss qilmaslik
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.8),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return TelegramStyleVideoRecorder(taskId: task.id, maxDuration: 40);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );

    setState(() => _isRecording = false);

    if (!context.mounted) return;

    if (result != null) {
      // Agar List<XFile> bo'lsa
      if (result is List<XFile>) {
        await _uploadVideoSegments(task, result);
      }
      // Agar bitta XFile bo'lsa
      else if (result is XFile) {
        await _uploadVideo(task, result);
      }
    }
  }

  /// Video yozuvni to'xtatish
  void _stopRecording() {
    if (_isRecording) {
      Navigator.of(context).pop(); // Dialogni yopish
      setState(() => _isRecording = false);
    }
  }

  /// Barcha video segmentlarni yuborish
  Future<void> _uploadVideoSegments(
    TaskWorkerModel task,
    List<XFile> segments,
  ) async {
    try {
      bool success = await TaskWorkerService().completeTaskWithSegments(
        taskId: task.id,
        segments: segments,
      );

      if (success) {
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Muvaffaqiyatli yuborildi!"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Yuborishda xatolik!"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Xatolik: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Videoni serverga yuborish
  Future<void> _uploadVideo(TaskWorkerModel task, XFile video) async {
    try {
      final requestData = RequestTaskModel(id: task.id, file: video);
      bool success = await TaskWorkerService().completeTask(requestData);

      if (success) {
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Muvaffaqiyatli yuborildi!"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Yuborishda xatolik!"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Xatolik: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(user?.username ?? ""),
        actions: [
          // Yozish paytida stop tugmasi
          if (_isRecording)
            IconButton(
              onPressed: _stopRecording,
              icon: const Icon(Icons.stop_circle, color: Colors.red),
              tooltip: "To'xtatish",
            ),
          IconButton(
            onPressed: () async {
              await LogOutService().logOut();

              tokenStorage.removeToken();
              tokenStorage.putUserData({});
              context.pushAndRemove(LoginPage());
            },
            icon: const Icon(Icons.logout),
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
                onTap: tasks[i].videoUrl == null
                    ? null
                    : () => showDialog(
                        context: context,
                        barrierColor: Colors.black87,
                        builder: (context) => CircleVideoPlayer(
                          videoUrl: "${AppUrls.baseUrl}/${tasks[i].videoUrl}",
                          isLocal: false,
                        ),
                      ),
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
                              "${tasks[i].id}. ${tasks[i].description}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (tasks[i].submittedBy != null)
                              Text(
                                "${tasks[i].submittedBy} | ${tasks[i].submittedAt?.toLocal().hour.toString().padLeft(2, '0')}:${tasks[i].submittedAt?.minute.toString().padLeft(2, '0')}",
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _isRecording
                            ? null
                            : () => _showVideoRecorder(tasks[i]),
                        icon: Icon(
                          _isRecording
                              ? Icons.fiber_manual_record
                              : Icons.videocam,
                          color: Colors.grey.shade600,
                        ),
                      ),
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
