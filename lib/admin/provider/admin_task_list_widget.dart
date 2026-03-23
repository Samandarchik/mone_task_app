import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/provider/admin_task_item.dart';
import 'package:mone_task_app/admin/provider/video_download_provider.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class AdminTaskListWidget extends StatefulWidget {
  final List<TaskModel> tasks;
  final int filialId;
  final DateTime selectedDate;
  final String role;
  final VoidCallback onRefresh;
  final Function(
    List<String> videoPaths,
    int startIndex,
    List<TaskModel> task,
  )
  onShowVideoPlayer;

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final downloadProvider = context.read<VideoDownloadProvider>();
      downloadProvider.startDownloadsForTasks(widget.tasks, widget.filialId);
    });
  }

  @override
  void didUpdateWidget(AdminTaskListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks != widget.tasks ||
        oldWidget.filialId != widget.filialId) {
      final downloadProvider = context.read<VideoDownloadProvider>();
      downloadProvider.startDownloadsForTasks(widget.tasks, widget.filialId);
    }
  }

  /// Faqat videoli tasklar ro'yxati
  List<TaskModel> _getVideoTasks() {
    return widget.tasks
        .where((t) => t.videoUrl != null && t.videoUrl!.isNotEmpty)
        .toList();
  }

  /// Faqat videoli tasklar uchun resolved path'lar
  List<String> _getVideoPaths(VideoDownloadProvider downloadProvider) {
    return _getVideoTasks().map((t) {
      final fullUrl = downloadProvider.getFullUrl(t.videoUrl!);
      return downloadProvider.resolvedPath(fullUrl);
    }).toList();
  }

  /// Berilgan task videoli tasklar ichida nechanchi index da turganini topish
  int _getVideoIndex(TaskModel task) {
    final videoTasks = _getVideoTasks();
    return videoTasks.indexWhere((t) => t.taskId == task.taskId);
  }

  void _shareTaskLink(TaskModel task) {
    final link = 'https://taskapi.monebakeryuz.uz/task/${task.date}/${task.taskId}';
    Share.share('${task.task}\n$link', subject: task.task);
  }

  @override
  Widget build(BuildContext context) {
    final downloadProvider = context.watch<VideoDownloadProvider>();

    // tasks allaqachon filial + status bo'yicha filterlangan
    final filtered = widget.tasks;

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
            fullVideoUrl = downloadProvider.getFullUrl(task.videoUrl!);
          }

          final videoState = fullVideoUrl != null
              ? downloadProvider.getState(fullVideoUrl)
              : const VideoDownloadState();

          String? videoPath;
          if (fullVideoUrl != null) {
            videoPath = downloadProvider.resolvedPath(fullVideoUrl);
          }

          return AdminTaskListItem(
            index: i + 1,
            task: task,
            role: widget.role,
            videoPath: videoPath,
            videoStatus: videoState.status,
            downloadProgress: videoState.progress,
            selectedDate: widget.selectedDate,
            onRefresh: widget.onRefresh,
            onShowVideoPlayer: (path) {
              // ── MUHIM: faqat videoli tasklar va to'g'ri index ──────────
              final hasVideo =
                  task.videoUrl != null && task.videoUrl!.isNotEmpty;
              if (!hasVideo) return; // videosiz task — hech narsa qilmaymiz

              final allVideoPaths = _getVideoPaths(downloadProvider);
              final videoTasks = _getVideoTasks();
              final startIndex = _getVideoIndex(task);

              if (startIndex < 0 || allVideoPaths.isEmpty) return;

              widget.onShowVideoPlayer(
                allVideoPaths,
                startIndex,
                videoTasks, // ← faqat videoli tasklar
              );
            },
            onShareVideo: () => _shareTaskLink(task),
          );
        },
      ),
    );
  }
}
