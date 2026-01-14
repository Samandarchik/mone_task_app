import 'package:flutter/material.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/checker/ui/player.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/utils/get_color.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class CheckerHomeUi extends StatefulWidget {
  const CheckerHomeUi({super.key});

  @override
  State<CheckerHomeUi> createState() => _CheckerHomeUiState();
}

class _CheckerHomeUiState extends State<CheckerHomeUi> {
  late Future<List<CheckerCheckTaskModel>> tasksFuture;

  // Video cache uchun
  Map<String, String> cachedVideos = {}; // videoUrl: local file path
  Set<String> downloadingVideos = {}; // hozir yuklanayotgan videolar

  @override
  void initState() {
    super.initState();
    tasksFuture = AdminTaskService().fetchTasks(selectedDate);
    getUserFullName();
    _loadCachedVideos();
  }

  String fullName = "";

  void getUserFullName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      fullName = prefs.getString('full_name') ?? '';
    });
  }

  // Mavjud cache'langan videolarni yuklash
  Future<void> _loadCachedVideos() async {
    final directory = await getApplicationDocumentsDirectory();
    final videosDir = Directory('${directory.path}/videos');

    if (!await videosDir.exists()) {
      await videosDir.create(recursive: true);
      return;
    }

    final files = videosDir.listSync();
    for (var file in files) {
      if (file is File) {
        // Fayl nomidan URL ni tiklash
        final fileName = file.path.split('/').last;
        // Bu yerda URL mapping kerak bo'ladi
        // Hozircha faqat local path'ni saqlaymiz
      }
    }
  }

  // Video URL'dan local file path olish
  Future<String> _getLocalFilePath(String videoUrl) async {
    final directory = await getApplicationDocumentsDirectory();
    final videosDir = Directory('${directory.path}/videos');

    if (!await videosDir.exists()) {
      await videosDir.create(recursive: true);
    }

    final fileName = videoUrl
        .split('/')
        .last
        .replaceAll(RegExp(r'[^\w\s\-\.]'), '_');

    return '${videosDir.path}/$fileName';
  }

  // Videoni cache'dan olish yoki yuklab olish
  Future<String> _getCachedOrDownloadVideo(String videoUrl) async {
    // Agar cache'da bo'lsa, local path qaytarish
    if (cachedVideos.containsKey(videoUrl)) {
      final localPath = cachedVideos[videoUrl]!;
      final file = File(localPath);
      if (await file.exists() && await file.length() > 0) {
        return localPath;
      }
    }

    // Agar hozir yuklanayotgan bo'lsa, network URL qaytarish
    if (downloadingVideos.contains(videoUrl)) {
      return videoUrl;
    }

    // Yuklab olishni boshlash (background'da)
    _downloadVideoInBackground(videoUrl);

    // Hozircha network URL qaytarish
    return videoUrl;
  }

  // Video'ni background'da yuklab olish
  Future<void> _downloadVideoInBackground(String videoUrl) async {
    if (downloadingVideos.contains(videoUrl)) {
      return; // Allaqachon yuklanayapti
    }

    setState(() {
      downloadingVideos.add(videoUrl);
    });

    try {
      final localPath = await _getLocalFilePath(videoUrl);
      final file = File(localPath);

      // Agar allaqachon mavjud bo'lsa
      if (await file.exists() && await file.length() > 0) {
        setState(() {
          cachedVideos[videoUrl] = localPath;
          downloadingVideos.remove(videoUrl);
        });
        return;
      }

      final dio = Dio();
      await dio.download(videoUrl, localPath);

      if (await file.exists() && await file.length() > 0) {
        setState(() {
          cachedVideos[videoUrl] = localPath;
          downloadingVideos.remove(videoUrl);
        });
      }
    } catch (e) {
      print('Video yuklashda xatolik: $videoUrl - $e');
      setState(() {
        downloadingVideos.remove(videoUrl);
      });
    }
  }

  void _showCircleVideoPlayer(String videoPath) async {
    // 1) To'liq URL yasaymiz
    String realUrl = videoPath.startsWith('http')
        ? videoPath
        : '${AppUrls.baseUrl}/$videoPath';

    // 2) Localdan yuklangan bo'lsa → local path qaytadi
    String finalUrl = await _getCachedOrDownloadVideo(realUrl);

    // 3) Video mavjudligini tekshiramiz
    final file = File(finalUrl);
    bool isLocalExists = await file.exists() && await file.length() > 0;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => CircleVideoPlayer(
        videoUrl: isLocalExists ? file.path : realUrl,
        isLocal: isLocalExists,
      ),
    );
  }

  DateTime selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            GestureDetector(
              child: Text(
                selectedDate.day == DateTime.now().day
                    ? "Сегодня "
                    : "${selectedDate.day}/${selectedDate.month}/${selectedDate.year} ",
              ),
              onTap: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now().subtract(const Duration(days: 5)),
                  initialDate: selectedDate,
                  lastDate: DateTime.now(),
                );

                if (picked != null) {
                  setState(() {
                    selectedDate = picked;
                    tasksFuture = AdminTaskService().fetchTasks(selectedDate);
                  });
                }
              },
            ),
          ],
          title: Text(fullName),
          leading: IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              SharedPreferences prefs = await SharedPreferences.getInstance();
              prefs.remove("access_token");
              prefs.remove("role");
              context.pushAndRemove(LoginPage());
            },
          ),
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
                          tasksFuture = AdminTaskService().fetchTasks(
                            selectedDate,
                          );
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

            // Barcha videolarni background'da yuklab olishni boshlash
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _preloadVideos(allTasks);
            });

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

  // Videolarni oldindan yuklash (background)
  void _preloadVideos(List<CheckerCheckTaskModel> tasks) {
    final videoUrls = tasks
        .where((task) => task.videoUrl != null && task.videoUrl!.isNotEmpty)
        .map((task) {
          String url = task.videoUrl!;
          if (!url.startsWith('http')) {
            url = '${AppUrls.baseUrl}/$url';
          }
          return url;
        })
        .toSet()
        .toList();

    for (String url in videoUrls) {
      _downloadVideoInBackground(url);
    }
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
        final newTasks = AdminTaskService().fetchTasks(selectedDate);
        setState(() {
          tasksFuture = newTasks;
        });
        await newTasks;
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          String? videoUrl = filtered[i].videoUrl;
          if (videoUrl != null &&
              videoUrl.isNotEmpty &&
              !videoUrl.startsWith('http')) {
            videoUrl = '${AppUrls.baseUrl}/$videoUrl';
          }

          bool isVideoCached =
              videoUrl != null && cachedVideos.containsKey(videoUrl);
          bool isDownloading =
              videoUrl != null && downloadingVideos.contains(videoUrl);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            color: getStatusColor(filtered[i].status),
            child: InkWell(
              onLongPress: () async {
                final bool isDelete = await AdminTaskService().updateTaskStatus(
                  filtered[i].taskId,
                  1,
                );
                if (isDelete) {
                  setState(() {
                    tasksFuture = AdminTaskService().fetchTasks(selectedDate);
                  });
                }
              },
              onTap: () async {
                if (filtered[i].videoUrl != null &&
                    filtered[i].videoUrl!.isNotEmpty) {
                  if (selectedDate.day == DateTime.now().day) {
                    final bool isSucsess = await AdminTaskService()
                        .updateTaskStatus(filtered[i].taskId, 3);
                    if (isSucsess) {
                      setState(() {
                        filtered[i].status = 3;
                      });
                    }
                  }
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
                              color: isVideoCached
                                  ? Colors.green
                                  : (isDownloading
                                        ? Colors.orange
                                        : Colors.blue),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isDownloading)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                else
                                  Icon(
                                    isVideoCached
                                        ? Icons.check_circle
                                        : Icons.cloud_download,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                const SizedBox(width: 4),
                                Text(
                                  isDownloading
                                      ? "Yuklanmoqda..."
                                      : (isVideoCached ? "Yuklangan" : "Video"),
                                  style: const TextStyle(
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
          );
        },
      ),
    );
  }
}
