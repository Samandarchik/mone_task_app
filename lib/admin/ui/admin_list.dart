import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/ui/audio_task_row.dart';
import 'package:mone_task_app/admin/ui/dialog.dart';
import 'package:mone_task_app/admin/ui/edit_task_ui.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/utils/get_color.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AdminTaskListWidget extends StatefulWidget {
  final List<CheckerCheckTaskModel> tasks;
  final int filialId;
  final DateTime selectedDate;
  final String role;

  final VoidCallback onRefresh;
  final Function(List<String> videoPaths, int startIndex) onShowVideoPlayer;

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

  String _getFullUrl(String originalUrl) {
    if (originalUrl.startsWith('http://') ||
        originalUrl.startsWith('https://')) {
      return originalUrl;
    }
    return '${AppUrls.baseUrl}/$originalUrl';
  }

  Future<void> _downloadVideoInBackground(String videoUrl) async {
    if (downloadingVideos.contains(videoUrl)) return;

    if (mounted) setState(() => downloadingVideos.add(videoUrl));

    try {
      final localPath = await _getLocalFilePath(videoUrl);
      final file = File(localPath);

      // Allaqachon to'liq yuklangan faylni tekshirish
      if (await file.exists() && await file.length() > 0) {
        // Content-length bilan solishtirish
        try {
          final dio = Dio();
          final head = await dio.head(videoUrl);
          final serverSize = int.tryParse(
            head.headers.value('content-length') ?? '',
          );
          final localSize = await file.length();

          if (serverSize != null && localSize < serverSize) {
            // Yarim yuklangan — o'chiramiz
            await file.delete();
          } else {
            // To'liq
            if (mounted) {
              setState(() {
                cachedVideos[videoUrl] = localPath;
                downloadingVideos.remove(videoUrl);
              });
            }
            return;
          }
        } catch (_) {
          // HEAD ishlamasa, mavjud faylni ishlatamiz
          if (mounted) {
            setState(() {
              cachedVideos[videoUrl] = localPath;
              downloadingVideos.remove(videoUrl);
            });
          }
          return;
        }
      }

      // ✅ TEMP faylga yuklaymiz (yarim qolsa asosiy faylga ta'sir qilmaydi)
      final tempPath = '$localPath.tmp';
      final tempFile = File(tempPath);

      final dio = Dio();
      await dio.download(videoUrl, tempPath);

      // Yuklash tugagandan keyin validatsiya
      if (await tempFile.exists() && await tempFile.length() > 0) {
        // Server hajmi bilan tekshirish
        try {
          final head = await dio.head(videoUrl);
          final serverSize = int.tryParse(
            head.headers.value('content-length') ?? '',
          );
          final downloadedSize = await tempFile.length();

          if (serverSize != null && downloadedSize < serverSize) {
            // To'liq yuklanmagan — o'chirib tashlaymiz
            await tempFile.delete();
            if (mounted) setState(() => downloadingVideos.remove(videoUrl));
            return;
          }
        } catch (_) {}

        // ✅ To'liq yuklangan — rename qilamiz
        await tempFile.rename(localPath);

        if (mounted) {
          setState(() {
            cachedVideos[videoUrl] = localPath;
            downloadingVideos.remove(videoUrl);
          });
        }
      } else {
        if (await tempFile.exists()) await tempFile.delete();
        if (mounted) setState(() => downloadingVideos.remove(videoUrl));
      }
    } catch (e) {
      // Xatolikda temp faylni tozalash
      try {
        final localPath = await _getLocalFilePath(videoUrl);
        final tempFile = File('$localPath.tmp');
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      if (mounted) setState(() => downloadingVideos.remove(videoUrl));
    }
  }

  void _preloadVideos() {
    final filteredTasks = widget.tasks
        .where((t) => t.filialId == widget.filialId)
        .toList();

    final videoUrls = filteredTasks
        .where((t) => t.videoUrl != null && t.videoUrl!.isNotEmpty)
        .map((t) => _getFullUrl(t.videoUrl!))
        .toSet()
        .toList();

    for (final url in videoUrls) {
      _downloadVideoInBackground(url);
    }
  }

  List<String> _getAllVideoPaths() {
    return widget.tasks
        .where(
          (t) =>
              t.filialId == widget.filialId &&
              t.videoUrl != null &&
              t.videoUrl!.isNotEmpty,
        )
        .map((t) {
          final fullUrl = _getFullUrl(t.videoUrl!);
          return cachedVideos[fullUrl] ?? fullUrl;
        })
        .toList();
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

      final fullUrl = _getFullUrl(videoUrl);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator.adaptive()),
        );
      }

      String? localPath;

      if (cachedVideos.containsKey(fullUrl)) {
        localPath = cachedVideos[fullUrl];
      } else {
        localPath = await _getLocalFilePath(fullUrl);
        final file = File(localPath);
        if (!await file.exists() || await file.length() == 0) {
          final dio = Dio();
          await dio.download(fullUrl, localPath);
        }
        if (mounted) setState(() => cachedVideos[fullUrl] = localPath!);
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
        padding: const EdgeInsets.all(8),
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final task = filtered[i];

          String? fullVideoUrl;
          if (task.videoUrl != null && task.videoUrl!.isNotEmpty) {
            fullVideoUrl = _getFullUrl(task.videoUrl!);
          }

          final bool isVideoCached =
              fullVideoUrl != null && cachedVideos.containsKey(fullVideoUrl);
          final bool isDownloading =
              fullVideoUrl != null && downloadingVideos.contains(fullVideoUrl);

          String? videoPath;
          if (fullVideoUrl != null) {
            videoPath = isVideoCached
                ? cachedVideos[fullVideoUrl]
                : fullVideoUrl;
          }

          final videoTasksInOrder = filtered
              .where((t) => t.videoUrl != null && t.videoUrl!.isNotEmpty)
              .toList();
          final videoIndex = videoTasksInOrder.indexWhere(
            (t) => t.taskId == task.taskId,
          );

          return AdminTaskListItem(
            index: i + 1,
            task: task,
            role: widget.role,
            videoPath: videoPath,
            isVideoCached: isVideoCached,
            isDownloading: isDownloading,
            selectedDate: widget.selectedDate,
            onRefresh: widget.onRefresh,
            onShowVideoPlayer: (path) {
              final allPaths = _getAllVideoPaths();
              final startIndex = videoIndex >= 0 ? videoIndex : 0;
              widget.onShowVideoPlayer(allPaths, startIndex);
            },
            onShareVideo: () => _shareVideo(task),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class AdminTaskListItem extends StatefulWidget {
  final int index;
  final CheckerCheckTaskModel task;
  final String? videoPath;
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
    required this.index,
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

class _AdminTaskListItemState extends State<AdminTaskListItem>
    with SingleTickerProviderStateMixin {
  late CheckerCheckTaskModel task;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    task = widget.task;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(AdminTaskListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task != widget.task) {
      task = widget.task;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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
          if (widget.videoPath != null) {
            if (widget.selectedDate.day == DateTime.now().day) {
              final bool isSuccess = await AdminTaskService().updateTaskStatus(
                task.taskId,
                3,
                widget.selectedDate,
              );
              if (isSuccess && mounted) {
                setState(() => task.status = 3);
              }
            }
            widget.onShowVideoPlayer(widget.videoPath!);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${widget.index}. ${task.task}",
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
                            if (task.videoUrl != null &&
                                task.videoUrl!.isNotEmpty)
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
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : Icon(
                                        widget.isVideoCached
                                            ? Icons.check_circle
                                            : Icons.cloud_download,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Share button
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

              // ── Audio row ────────────────────────────────────────────────
              const SizedBox(height: 8),
              const SizedBox(height: 6),
              AudioTaskRow(task: task, selectedDate: widget.selectedDate),
            ],
          ),
        ),
      ),
    );
  }
}
