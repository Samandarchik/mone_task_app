import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  final ImagePicker _picker = ImagePicker();
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

/// Telegram uslubidagi video recorder dialog
class VideoRecorderDialog extends StatefulWidget {
  final int maxDuration;

  const VideoRecorderDialog({super.key, required this.maxDuration});

  @override
  State<VideoRecorderDialog> createState() => _VideoRecorderDialogState();
}

class _VideoRecorderDialogState extends State<VideoRecorderDialog> {
  bool _isRecording = false;
  int _secondsElapsed = 0;
  Timer? _timer;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _secondsElapsed = 0;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });

      if (_secondsElapsed >= widget.maxDuration) {
        _stopAndSave();
      }
    });
  }

  void _stopAndSave() async {
    _timer?.cancel();

    // Kameradan video olish
    final XFile? video = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: Duration(seconds: widget.maxDuration),
    );

    if (mounted) {
      Navigator.pop(context, video);
    }
  }

  void _cancel() {
    _timer?.cancel();
    Navigator.pop(context, null);
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Text(
              _isRecording ? "Yozilmoqda..." : "Video yozish",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Timer va progress
            if (_isRecording) ...[
              Text(
                _formatTime(_secondsElapsed),
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _secondsElapsed / widget.maxDuration,
                backgroundColor: Colors.grey.shade300,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
              ),
              const SizedBox(height: 8),
              Text(
                "Maksimal: ${widget.maxDuration} soniya",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ] else ...[
              Icon(Icons.videocam, size: 80, color: Colors.blue.shade400),
              const SizedBox(height: 16),
              Text(
                "Maksimal ${widget.maxDuration} soniya",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],

            const SizedBox(height: 32),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Cancel button
                ElevatedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.close),
                  label: const Text("Bekor qilish"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade300,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),

                // Record/Stop button
                ElevatedButton.icon(
                  onPressed: _isRecording ? _stopAndSave : _startRecording,
                  icon: Icon(
                    _isRecording ? Icons.stop : Icons.fiber_manual_record,
                  ),
                  label: Text(_isRecording ? "To'xtatish" : "Boshlash"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.red : Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
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
