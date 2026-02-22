import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/ui/audio_task_row.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/checker/ui/player2.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/utils/get_color.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class TaskListWidget extends StatefulWidget {
  final List<CheckerCheckTaskModel> tasks;
  final int filialId;
  final DateTime selectedDate;
  final VoidCallback onRefresh;
  final Function(String) onShowVideoPlayer;

  const TaskListWidget({
    super.key,
    required this.tasks,
    required this.filialId,
    required this.selectedDate,
    required this.onRefresh,
    required this.onShowVideoPlayer,
  });

  @override
  State<TaskListWidget> createState() => _TaskListWidgetState();
}

class _TaskListWidgetState extends State<TaskListWidget> {
  Map<String, String> cachedVideos = {};
  Set<String> downloadingVideos = {};

  @override
  void initState() {
    super.initState();
    _loadCachedVideos();
    _preloadVideos();
  }

  Future<void> _loadCachedVideos() async {
    final directory = await getApplicationDocumentsDirectory();
    final videosDir = Directory('${directory.path}/videos');
    if (!await videosDir.exists()) {
      await videosDir.create(recursive: true);
    }
  }

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

  Future<void> _downloadVideoInBackground(String videoUrl) async {
    if (downloadingVideos.contains(videoUrl)) return;

    if (mounted) setState(() => downloadingVideos.add(videoUrl));

    try {
      final localPath = await _getLocalFilePath(videoUrl);
      final file = File(localPath);

      if (await file.exists() && await file.length() > 0) {
        if (mounted) {
          setState(() {
            cachedVideos[videoUrl] = localPath;
            downloadingVideos.remove(videoUrl);
          });
        }
        return;
      }

      final dio = Dio();
      await dio.download(videoUrl, localPath);

      if (await file.exists() && await file.length() > 0) {
        if (mounted) {
          setState(() {
            cachedVideos[videoUrl] = localPath;
            downloadingVideos.remove(videoUrl);
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => downloadingVideos.remove(videoUrl));
    }
  }

  void _preloadVideos() {
    final filteredTasks = widget.tasks
        .where((task) => task.filialId == widget.filialId)
        .toList();

    final videoUrls = filteredTasks
        .where((task) => task.videoUrl != null && task.videoUrl!.isNotEmpty)
        .map((task) {
          String url = task.videoUrl!;
          if (!url.startsWith('http')) url = '${AppUrls.baseUrl}/$url';
          return url;
        })
        .toSet()
        .toList();

    for (final url in videoUrls) {
      _downloadVideoInBackground(url);
    }
  }

  Future<void> _shareVideo(CheckerCheckTaskModel task) async {
    try {
      String? videoUrl = task.videoUrl;
      if (videoUrl == null || videoUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Video topilmadi')));
        }
        return;
      }

      if (!videoUrl.startsWith('http')) {
        videoUrl = '${AppUrls.baseUrl}/$videoUrl';
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              const Center(child: CircularProgressIndicator.adaptive()),
        );
      }

      String? localPath;
      if (cachedVideos.containsKey(videoUrl)) {
        localPath = cachedVideos[videoUrl];
      } else {
        localPath = await _getLocalFilePath(videoUrl);
        final file = File(localPath);
        if (!await file.exists() || await file.length() == 0) {
          final dio = Dio();
          await dio.download(videoUrl, localPath);
        }
        if (mounted) setState(() => cachedVideos[videoUrl!] = localPath!);
      }

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

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
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  String? _getVideoPath(String? videoUrl) {
    if (videoUrl == null || videoUrl.isEmpty) return null;
    String fullUrl = videoUrl;
    if (!fullUrl.startsWith('http')) fullUrl = '${AppUrls.baseUrl}/$videoUrl';
    if (cachedVideos.containsKey(fullUrl)) return cachedVideos[fullUrl];
    return fullUrl;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.tasks
        .where((task) => task.filialId == widget.filialId)
        .toList();

    if (filtered.isEmpty) {
      return const Center(child: Text("Ushbu filial uchun task yo'q"));
    }

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      child: ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          String? videoUrl = filtered[i].videoUrl;
          if (videoUrl != null &&
              videoUrl.isNotEmpty &&
              !videoUrl.startsWith('http')) {
            videoUrl = '${AppUrls.baseUrl}/$videoUrl';
          }

          final isVideoCached =
              videoUrl != null && cachedVideos.containsKey(videoUrl);
          final isDownloading =
              videoUrl != null && downloadingVideos.contains(videoUrl);

          return TaskListItem(
            task: filtered[i],
            index: i,
            videoUrl: videoUrl,
            isVideoCached: isVideoCached,
            isDownloading: isDownloading,
            selectedDate: widget.selectedDate,
            onRefresh: widget.onRefresh,
            onShowVideoPlayer: widget.onShowVideoPlayer,
            onShareVideo: () => _shareVideo(filtered[i]),
            getVideoPath: _getVideoPath,
          );
        },
      ),
    );
  }
}

class TaskListItem extends StatefulWidget {
  final CheckerCheckTaskModel task;
  final String? videoUrl;
  final int index;
  final bool isVideoCached;
  final bool isDownloading;
  final DateTime selectedDate;
  final VoidCallback onRefresh;
  final Function(String) onShowVideoPlayer;
  final VoidCallback onShareVideo;
  final String? Function(String?) getVideoPath;

  const TaskListItem({
    super.key,
    required this.task,
    required this.index,
    required this.videoUrl,
    required this.isVideoCached,
    required this.isDownloading,
    required this.selectedDate,
    required this.onRefresh,
    required this.onShowVideoPlayer,
    required this.onShareVideo,
    required this.getVideoPath,
  });

  @override
  State<TaskListItem> createState() => _TaskListItemState();
}

class _TaskListItemState extends State<TaskListItem> {
  late CheckerCheckTaskModel task;

  @override
  void initState() {
    super.initState();
    task = widget.task;
  }

  @override
  void didUpdateWidget(TaskListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task != widget.task) {
      task = widget.task;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(5.0),
      child: Material(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 2,
        color: getStatusColor(task.status),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onLongPress: () async {
            if (task.videoUrl == null || task.videoUrl!.isEmpty) return;
            final bool isDelete = await AdminTaskService().updateTaskStatus(
              task.taskId,
              1,
              widget.selectedDate,
            );
            if (isDelete) widget.onRefresh();
          },
          onTap: () {
            if (task.videoUrl == null || task.videoUrl!.isEmpty) return;
            final videoPath = widget.getVideoPath(task.videoUrl);
            if (videoPath == null) return;

            showDialog(
              context: context,
              barrierColor: Colors.white12,
              builder: (context) => BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Center(
                  child: CircleVideoPlayer2(
                    videoUrl: videoPath,
                    onHalfWatched: () async {
                      // Status allaqachon 3 bo'lsa qayta so'rov ketmasin
                      if (task.status == 3) return;
                      final bool isSuccess = await AdminTaskService()
                          .updateTaskStatus(
                            task.taskId,
                            3,
                            widget.selectedDate,
                          );
                      if (isSuccess && mounted) {
                        setState(() => task.status = 3);
                      }
                    },
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
                // ── Asosiy qator: info + tugmalar ─────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${widget.index + 1}. ${task.task}",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (task.submittedBy != null)
                            Text(
                              "${task.submittedBy} | "
                              "${task.submittedAt?.toLocal().hour.toString().padLeft(2, '0')}:"
                              "${task.submittedAt?.minute.toString().padLeft(2, '0')}",
                            ),
                          const SizedBox(height: 2),
                          Text(
                            "${task.type == 1
                                ? "Ежедневно"
                                : task.type == 2
                                ? getWeekdaysString(task.days)
                                : task.days ?? ""}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
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
                            child: widget.isDownloading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator.adaptive(),
                                  )
                                : Icon(
                                    widget.isVideoCached
                                        ? Icons.check_circle
                                        : Icons.cloud_download,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                          ),
                        IconButton(
                          onPressed: () {
                            if (task.videoUrl != null &&
                                task.videoUrl!.isNotEmpty) {
                              widget.onShareVideo();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Video mavjud emas'),
                                ),
                              );
                            }
                          },
                          icon:
                              task.videoUrl != null && task.videoUrl!.isNotEmpty
                              ? const Icon(CupertinoIcons.share)
                              : const SizedBox(),
                        ),
                      ],
                    ),
                  ],
                ),

                // ── Audio yozish / tinglash (video bo'lsa chiqadi) ─────────
                AudioTaskRow(task: task, selectedDate: widget.selectedDate),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
