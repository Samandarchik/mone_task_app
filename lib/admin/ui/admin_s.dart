import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/ui/dialog.dart';
import 'package:mone_task_app/admin/ui/edit_task_ui.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/utils/get_color.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class AdminTaskListWidget extends StatefulWidget {
  final List<CheckerCheckTaskModel> tasks;
  final int filialId;
  final DateTime selectedDate;
  final String role;

  final VoidCallback onRefresh;
  final Function(String) onShowVideoPlayer;

  const AdminTaskListWidget({
    super.key,
    required this.tasks,
    required this.filialId,
    required this.role,
    required this.selectedDate,
    required this.onRefresh,
    required this.onShowVideoPlayer,
  });

  @override
  State<AdminTaskListWidget> createState() => _AdminTaskListWidgetState();
}

class _AdminTaskListWidgetState extends State<AdminTaskListWidget> {
  // Video cache uchun
  Map<String, String> cachedVideos = {};
  Set<String> downloadingVideos = {};

  @override
  void initState() {
    super.initState();
    _loadCachedVideos();
    _preloadVideos();
  }

  // Mavjud cache'langan videolarni yuklash
  Future<void> _loadCachedVideos() async {
    final directory = await getApplicationDocumentsDirectory();
    final videosDir = Directory('${directory.path}/videos');

    if (!await videosDir.exists()) {
      await videosDir.create(recursive: true);
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

  // Original URL ni full URL ga aylantirish
  String _getFullUrl(String originalUrl) {
    if (originalUrl.startsWith('http://') ||
        originalUrl.startsWith('https://')) {
      return originalUrl;
    }
    return '${AppUrls.baseUrl}/$originalUrl';
  }

  // Video'ni background'da yuklab olish
  Future<void> _downloadVideoInBackground(String videoUrl) async {
    if (downloadingVideos.contains(videoUrl)) {
      return;
    }

    if (mounted) {
      setState(() {
        downloadingVideos.add(videoUrl);
      });
    }

    try {
      final localPath = await _getLocalFilePath(videoUrl);
      final file = File(localPath);

      // Agar allaqachon mavjud bo'lsa
      if (await file.exists() && await file.length() > 0) {
        if (mounted) {
          setState(() {
            cachedVideos[videoUrl] = localPath;
            downloadingVideos.remove(videoUrl);
          });
        }
        print('Admin: Video allaqachon cache\'da: $videoUrl -> $localPath');
        return;
      }

      print('Admin: Video yuklanmoqda: $videoUrl -> $localPath');
      final dio = Dio();
      await dio.download(videoUrl, localPath);

      if (await file.exists() && await file.length() > 0) {
        if (mounted) {
          setState(() {
            cachedVideos[videoUrl] = localPath;
            downloadingVideos.remove(videoUrl);
          });
        }
        print('Admin: Video muvaffaqiyatli yuklandi: $videoUrl -> $localPath');
      }
    } catch (e) {
      print('Admin: Video yuklashda xatolik: $videoUrl - $e');
      if (mounted) {
        setState(() {
          downloadingVideos.remove(videoUrl);
        });
      }
    }
  }

  // Videolarni oldindan yuklash (background)
  void _preloadVideos() {
    final filteredTasks = widget.tasks
        .where((task) => task.filialId == widget.filialId)
        .toList();

    final videoUrls = filteredTasks
        .where((task) => task.videoUrl != null && task.videoUrl!.isNotEmpty)
        .map((task) => _getFullUrl(task.videoUrl!))
        .toSet()
        .toList();

    for (String url in videoUrls) {
      _downloadVideoInBackground(url);
    }
  }

  // Video ulashish funksiyasi
  Future<void> _shareVideo(CheckerCheckTaskModel task) async {
    try {
      // Video URL'ni to'liq shakliga keltirish
      String? videoUrl = task.videoUrl;
      if (videoUrl == null || videoUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Video topilmadi')));
        }
        return;
      }

      final fullUrl = _getFullUrl(videoUrl);

      // Loading ko'rsatish
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator.adaptive()),
        );
      }

      String? localPath;

      // Agar video cache'da bo'lsa, uni ishlatamiz
      if (cachedVideos.containsKey(fullUrl)) {
        localPath = cachedVideos[fullUrl];
      } else {
        // Aks holda yuklab olamiz
        localPath = await _getLocalFilePath(fullUrl);
        final file = File(localPath);

        // Agar fayl mavjud bo'lmasa, yuklab olamiz
        if (!await file.exists() || await file.length() == 0) {
          final dio = Dio();
          await dio.download(fullUrl, localPath);
        }

        // Cache'ga qo'shamiz
        if (mounted) {
          setState(() {
            cachedVideos[fullUrl] = localPath!;
          });
        }
      }

      // Loading yopish
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Video faylini ulashish
      final file = File(localPath!);
      if (await file.exists() && await file.length() > 0) {
        await Share.shareXFiles([
          XFile(file.path),
        ], text: 'Задача: ${task.task}');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Video fayl topilmadi')));
        }
      }
    } catch (e) {
      // Loading yopish (agar xatolik bo'lsa)
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      print('Admin: Share xatolik: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    List<CheckerCheckTaskModel> filtered = widget.tasks
        .where((task) => task.filialId == widget.filialId)
        .toList();

    if (filtered.isEmpty) {
      return const Center(child: Text("Ushbu filial uchun task yo'q"));
    }

    return RefreshIndicator(
      onRefresh: () async {
        widget.onRefresh();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final task = filtered[i];

          // Full URL olish
          String? fullVideoUrl;
          if (task.videoUrl != null && task.videoUrl!.isNotEmpty) {
            fullVideoUrl = _getFullUrl(task.videoUrl!);
          }

          bool isVideoCached =
              fullVideoUrl != null && cachedVideos.containsKey(fullVideoUrl);
          bool isDownloading =
              fullVideoUrl != null && downloadingVideos.contains(fullVideoUrl);

          // Video path olish (local yoki online)
          String? videoPath;
          if (fullVideoUrl != null) {
            if (isVideoCached) {
              videoPath = cachedVideos[fullVideoUrl]; // Local path
            } else {
              videoPath = fullVideoUrl; // Online URL
            }
          }

          return AdminTaskListItem(
            task: task,
            role: widget.role,
            videoPath: videoPath,
            isVideoCached: isVideoCached,
            isDownloading: isDownloading,
            selectedDate: widget.selectedDate,
            onRefresh: widget.onRefresh,
            onShowVideoPlayer: widget.onShowVideoPlayer,
            onShareVideo: () => _shareVideo(task),
          );
        },
      ),
    );
  }
}

class AdminTaskListItem extends StatefulWidget {
  final CheckerCheckTaskModel task;
  final String? videoPath; // Bu local yoki online path bo'lishi mumkin
  final bool isVideoCached;
  final bool isDownloading;
  final DateTime selectedDate;
  final String role;

  final VoidCallback onRefresh;
  final Function(String) onShowVideoPlayer;
  final VoidCallback onShareVideo;

  const AdminTaskListItem({
    super.key,
    required this.task,
    required this.videoPath,
    required this.isVideoCached,
    required this.isDownloading,
    required this.selectedDate,
    required this.onRefresh,
    required this.onShowVideoPlayer,
    required this.role,
    required this.onShareVideo,
  });

  @override
  State<AdminTaskListItem> createState() => _AdminTaskListItemState();
}

class _AdminTaskListItemState extends State<AdminTaskListItem> {
  late CheckerCheckTaskModel task;

  @override
  void initState() {
    super.initState();
    task = widget.task;
  }

  @override
  void didUpdateWidget(AdminTaskListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task != widget.task) {
      task = widget.task;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      color: getStatusColor(task.status),
      child: InkWell(
        onLongPress: () async {
          final isDelete = await NativeDialog.showDeleteDialog();

          if (isDelete) {
            await AdminTaskService().deleteTask(task.taskId);
            widget.onRefresh();
          }
        },
        onDoubleTap: () async {
          context.push(EditTaskUi(task: task));
        },
        onTap: () async {
          if (widget.videoPath != null || widget.role == "super_admin") {
            if (widget.selectedDate.day == DateTime.now().day) {
              final bool isSucsess = await AdminTaskService().updateTaskStatus(
                task.taskId,
                3,
                widget.selectedDate,
              );
              if (isSucsess && mounted) {
                setState(() {
                  task.status = 3;
                });
              }
            }

            // Video path ni to'g'ridan-to'g'ri yuboramiz (local yoki online)
            widget.onShowVideoPlayer(widget.videoPath!);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.task,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (task.submittedBy != null)
                      Text(
                        "${task.submittedBy} | ${task.submittedAt?.toLocal().hour.toString().padLeft(2, '0')}:${task.submittedAt?.minute.toString().padLeft(2, '0')}",
                      ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "${getTypeName(task.type)} ${task.type == 2 ? getWeekdaysString(task.days) : task.days ?? ""}",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black,
                          ),
                        ),
                        if (task.videoUrl != null && task.videoUrl!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: widget.isVideoCached
                                  ? Colors.green
                                  : (widget.isDownloading
                                        ? Colors.orange
                                        : Colors.blue),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.isDownloading)
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
                                    widget.isVideoCached
                                        ? Icons.check_circle
                                        : Icons.cloud_download,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  if (task.videoUrl != null && task.videoUrl!.isNotEmpty) {
                    widget.onShareVideo();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Video mavjud emas')),
                    );
                  }
                },
                icon: task.videoUrl != null && task.videoUrl!.isNotEmpty
                    ? const Icon(CupertinoIcons.share)
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
