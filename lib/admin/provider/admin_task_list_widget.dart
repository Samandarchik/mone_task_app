import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/video_download_provider.dart';
import 'package:mone_task_app/admin/ui/dialog.dart';
import 'package:mone_task_app/admin/ui/edit_task_ui.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/utils/get_color.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class AdminTaskListWidget extends StatefulWidget {
  final List<CheckerCheckTaskModel> tasks;
  final int filialId;
  final DateTime selectedDate;
  final String role;
  final VoidCallback onRefresh;
  final Function(
    List<String> videoPaths,
    int startIndex,
    List<CheckerCheckTaskModel> task,
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
    // Start downloads via provider (replaces global static cache)
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

  Future<void> _shareVideo(
    CheckerCheckTaskModel task,
    VideoDownloadProvider downloadProvider,
  ) async {
    try {
      final videoUrl = task.videoUrl;
      if (videoUrl == null || videoUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Video topilmadi')));
        }
        return;
      }

      final fullUrl = downloadProvider.getFullUrl(videoUrl);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              const Center(child: CircularProgressIndicator.adaptive()),
        );
      }

      String localPath;

      if (downloadProvider.isCached(fullUrl)) {
        localPath = downloadProvider.getLocalPath(fullUrl)!;
      } else {
        // Download directly for sharing
        final directory = await getApplicationDocumentsDirectory();
        final fileName = fullUrl
            .split('/')
            .last
            .replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
        localPath = '${directory.path}/videos/$fileName';
        final file = File(localPath);
        if (!await file.exists() || await file.length() == 0) {
          await Dio().download(fullUrl, localPath);
        }
      }

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      final file = File(localPath);
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
    final downloadProvider = context.watch<VideoDownloadProvider>();

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
            fullVideoUrl = downloadProvider.getFullUrl(task.videoUrl!);
          }

          final videoState = fullVideoUrl != null
              ? downloadProvider.getState(fullVideoUrl)
              : const VideoDownloadState();

          String? videoPath;
          if (fullVideoUrl != null) {
            videoPath = downloadProvider.resolvedPath(fullVideoUrl);
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
            videoStatus: videoState.status,
            downloadProgress: videoState.progress,
            selectedDate: widget.selectedDate,
            onRefresh: widget.onRefresh,
            onShowVideoPlayer: (path) {
              final allPaths = downloadProvider.getAllVideoPaths(
                widget.tasks,
                widget.filialId,
              );
              final startIndex = videoIndex >= 0 ? videoIndex : 0;
              widget.onShowVideoPlayer(allPaths, startIndex, filtered);
            },
            onShareVideo: () => _shareVideo(task, downloadProvider),
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
  final VideoStatus videoStatus;
  final double downloadProgress;
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
    required this.videoStatus,
    required this.downloadProgress,
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

  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;

  bool _isLandscape(BuildContext context) =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  @override
  Widget build(BuildContext context) {
    if (_isTablet(context) && _isLandscape(context)) {
      return _buildTabletLandscapeCard(context);
    }
    return _buildDefaultCard(context);
  }

  Widget _buildDefaultCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      color: Colors.white70,
      child: InkWell(
        onLongPress: _handleLongPress,
        onDoubleTap: _handleDoubleTap,
        onTap: _handleTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildTaskInfo(context, showBadge: true)),
              _buildShareButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabletLandscapeCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      color: Colors.white70,
      child: InkWell(
        onLongPress: _handleLongPress,
        onDoubleTap: _handleDoubleTap,
        onTap: _handleTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 65,
                child: _buildTaskInfo(context, showBadge: false),
              ),
              const SizedBox(width: 16),
              if (task.videoUrl != null && task.videoUrl!.isNotEmpty) ...[
                _buildVideoStatusBadge(),
                const SizedBox(width: 4),
              ],
              _buildShareButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskInfo(BuildContext context, {required bool showBadge}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "${widget.index}. ${task.task}",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        if (task.submittedBy != null)
          Text(
            "${task.submittedBy} | "
            "${task.submittedAt?.toLocal().hour.toString().padLeft(2, '0')}:"
            "${task.submittedAt?.minute.toString().padLeft(2, '0')}",
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                "${getTypeName(task.type)} ${task.type == 2 ? getWeekdaysString(task.days) : task.days ?? ""}",
                style: const TextStyle(fontSize: 12, color: Colors.black),
              ),
            ),
            if (showBadge && task.videoUrl != null && task.videoUrl!.isNotEmpty)
              _buildVideoStatusBadge(),
          ],
        ),
      ],
    );
  }

  Widget _buildShareButton(BuildContext context) {
    if (task.videoUrl == null || task.videoUrl!.isEmpty) {
      return const SizedBox.shrink();
    }
    return IconButton(
      onPressed: widget.onShareVideo,
      icon: const Icon(CupertinoIcons.share),
    );
  }

  Widget _buildVideoStatusBadge() {
    switch (widget.videoStatus) {
      case VideoStatus.cached:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 14, color: Colors.white),
              SizedBox(width: 4),
              Text(
                '100%',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );

      case VideoStatus.downloading:
        final percent = (widget.downloadProgress * 100).toInt();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  value: widget.downloadProgress > 0
                      ? widget.downloadProgress
                      : null,
                  strokeWidth: 2,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  backgroundColor: Colors.white30,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$percent%',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );

      case VideoStatus.error:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.error_outline, size: 16, color: Colors.white),
        );

      case VideoStatus.notStarted:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.cloud_download,
            size: 16,
            color: Colors.white,
          ),
        );
    }
  }

  // ── Handlers ──────────────────────────────────────────────────────────

  Future<void> _handleLongPress() async {
    final isDelete = await NativeDialog.showDeleteDialog();
    if (isDelete) {
      final tasksProvider = context.read<AdminTasksProvider>();
      await tasksProvider.deleteTask(task.taskId);
      widget.onRefresh();
    }
  }

  Future<void> _handleDoubleTap() async {
    context.push(EditTaskUi(task: task));
  }

  Future<void> _handleTap() async {
    if (widget.videoPath != null) {
      if (task.status != 3) {
        final tasksProvider = context.read<AdminTasksProvider>();
        final isSuccess = await tasksProvider.updateTaskStatus(
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
  }
}
