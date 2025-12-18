import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mone_task_app/worker/model/task_worker_model.dart';
import 'package:mone_task_app/worker/model/response_task_model.dart';
import 'package:mone_task_app/worker/service/task_worker_service.dart';
import 'package:mone_task_app/worker/widgets/dealog.dart';
import 'package:http/http.dart' as http;

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

  /// 🔥 BACKEND GA YUBORISH
  Future<void> _uploadTaskToBackend(RequestTaskModel requestData) async {
    try {
      // Loading dialog ko'rsatish
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) =>
            const Center(child: CircularProgressIndicator.adaptive()),
      );

      final uri = Uri.parse("YOUR_API_URL/task/complete"); // ← API URL
      final request = http.MultipartRequest('POST', uri);

      // Task ma'lumotlarini qo'shish
      request.fields['task_id'] = requestData.id.toString();
      request.fields['worker_id'] =
          'USER_ID'; // ← User ID (SharedPreferences dan oling)
      request.fields['comment'] = requestData.text ?? '';

      // Agar fayl tanlangan bo'lsa
      if (requestData.file != null) {
        final file = await http.MultipartFile.fromPath(
          'file', // ← backend field nomi
          requestData.file!.path,
          filename: requestData.file!.name,
        );
        request.files.add(file);
      }

      // Yuborish
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      Navigator.pop(context); // Loading yopish

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Muvaffaqiyatli yuborildi!"),
            backgroundColor: Colors.green,
          ),
        );
        _refresh(); // Tasklar yangilanadi
      } else {
        throw Exception("Xatolik: ${response.statusCode}\n$responseBody");
      }
    } catch (e) {
      Navigator.pop(context); // Loading yopish
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Xatolik: $e"), backgroundColor: Colors.red),
      );
    }
  }

  /// 🔥 AVTOMATIK KAMERADAN VIDEO OLISH
  Future<void> _recordVideoAndUpload(TaskWorkerModel task) async {
    try {
      // Kameradan video olish
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 30),
      );

      // Agar video olinmasa (cancel bosilsa)
      if (video == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Video olinmadi"),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Video olingandan keyin backend ga yuborish
      final requestData = RequestTaskModel(
        id: task.id,
        text: "Video orqali bajarildi", // Default izoh
        file: video,
      );

      await _uploadTaskToBackend(requestData);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Xatolik: $e"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder(
          future: tasksFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }

            if (snapshot.hasError) {
              return Center(child: Text("Xatolik: ${snapshot.error}"));
            }

            List<TaskWorkerModel> tasks = snapshot.data ?? [];
            tasks = filterTasksByDate(tasks);

            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView.builder(
                itemCount: tasks.length,
                itemBuilder: (_, i) => InkWell(
                  onTap: () => _recordVideoAndUpload(tasks[i]),
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
                                "Type: ${tasks[i].taskType}",
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
      ),
    );
  }
}

/// 🔥 STATUS COLOR
Color getStatusColor(String status) {
  switch (status) {
    case "completed":
      return Colors.green.shade100;
    case "checking":
      return Colors.orange.shade100;
    default:
      return Colors.red.shade100;
  }
}

/// 🔥 TASK TYPE BO'YICHA FILTER
List<TaskWorkerModel> filterTasksByDate(List<TaskWorkerModel> tasks) {
  final now = DateTime.now();

  return tasks.where((task) {
    switch (task.taskType) {
      case "daily":
        return true;
      case "weekly":
        return now.weekday == DateTime.monday;
      case "monthly":
        return now.day == 1;
      default:
        return true;
    }
  }).toList();
}
