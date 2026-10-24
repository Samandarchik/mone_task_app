import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/provider/admin_task_item.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/task_view_sync.dart';
import 'package:mone_task_app/shared/widgets/task_reorder_list.dart';
import 'package:mone_task_app/admin/provider/video_download_provider.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:provider/provider.dart';
import 'package:mone_task_app/core/utils/share_helper.dart';

class AdminTaskListWidget extends StatefulWidget {
  final List<TaskModel> tasks;
  final int filialId;
  final DateTime selectedDate;
  final String role;
  final VoidCallback onRefresh;
  final Function(List<String> videoPaths, int startIndex, List<TaskModel> task)
  onShowVideoPlayer;

  /// Vazifa raqami yoki nomini ikki marta bosish — tahrirlash
  final ValueChanged<TaskModel>? onEditTask;

  /// «Все задачи» bilan bir joyda turish uchun
  final TaskSyncScope? syncScope;

  const AdminTaskListWidget({
    super.key,
    required this.tasks,
    required this.filialId,
    required this.role,
    required this.selectedDate,
    required this.onRefresh,
    required this.onShowVideoPlayer,
    this.onEditTask,
    this.syncScope,
  });

  @override
  State<AdminTaskListWidget> createState() => _AdminTaskListWidgetState();
}

class _AdminTaskListWidgetState extends State<AdminTaskListWidget>
    with TaskScrollSync {
  @override
  TaskSyncScope? get syncScope => widget.syncScope;

  @override
  int get syncFilialId => widget.filialId;

  @override
  List<int> get syncTemplateIds =>
      widget.tasks.map((t) => t.templateId).toList();

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
      // didUpdateWidget build paytida chaqiriladi — provider notifyListeners
      // qilsa "element.dirty" assertion chiqadi. Shuning uchun frame'dan keyin.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<VideoDownloadProvider>().startDownloadsForTasks(
          widget.tasks,
          widget.filialId,
        );
      });
    }
  }

  /// Taskning barcha videolari (multiVideo bo'lsa bir nechta)
  List<String> _taskVideos(TaskModel t) {
    if (t.videoUrls.isNotEmpty) return t.videoUrls;
    if (t.videoUrl != null && t.videoUrl!.isNotEmpty) return [t.videoUrl!];
    return const [];
  }

  /// [index] dan keyingi birinchi videoli taskning birinchi videosi
  String? _nextVideoUrl(List<TaskModel> tasks, int index) {
    for (var j = index + 1; j < tasks.length; j++) {
      final videos = tasks[j].allVideos;
      if (videos.isNotEmpty) return videos.first;
    }
    return null;
  }

  /// Har bir video uchun bitta yozuv — ko'p videoli task necha marta takrorlanadi,
  /// shunda player barcha videolarni ketma-ket ko'rsatadi
  List<TaskModel> _getVideoTasks() {
    return [
      for (final t in widget.tasks)
        for (final _ in _taskVideos(t)) t,
    ];
  }

  /// _getVideoTasks bilan bir xil tartibdagi resolved path'lar
  List<String> _getVideoPaths(VideoDownloadProvider downloadProvider) {
    return [
      for (final t in widget.tasks)
        for (final url in _taskVideos(t))
          downloadProvider.resolvedPath(downloadProvider.getFullUrl(url)),
    ];
  }

  /// Berilgan taskning birinchi videosi playlist ichida nechanchi index da
  int _getVideoIndex(TaskModel task) {
    final videoTasks = _getVideoTasks();
    return videoTasks.indexWhere((t) => t.taskId == task.taskId);
  }

  void _shareTaskLink(TaskModel task) {
    final link =
        'https://taskapi.monebakeryuz.uz/task/${task.date}/${task.taskId}';
    shareTaskLink(title: task.task, link: link, context: context);
  }

  @override
  Widget build(BuildContext context) {
    final downloadProvider = context.watch<VideoDownloadProvider>();
    final tasksProvider = context.watch<AdminTasksProvider>();

    // tasks allaqachon filial + status bo'yicha filterlangan
    final filtered = widget.tasks;

    if (filtered.isEmpty) {
      return const Center(child: Text("Ushbu filial uchun task yo'q"));
    }

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      // Telegram'dagidek: kartani bosib turib sudrab joyini o'zgartirish
      child: syncScrollListener(
        ReorderableListView.builder(
          // Ro'yxat qayta yaratilsa ham scroll joyi saqlanadi
          key: PageStorageKey('admin-tasks-${widget.filialId}'),
          scrollController: syncController,
          buildDefaultDragHandles: false,
          proxyDecorator: liftedTaskProxy,
          onReorderStart: reorderHaptic,
          onReorder: (o, n) =>
              tasksProvider.reorderVisible(filtered, o, n > o ? n - 1 : n),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
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

            return KeyedSubtree(
              key: ValueKey(task.taskId),
              child: KeyedSubtree(
                key: syncKey(task.templateId, task.taskId),
                child: AdminTaskListItem(
                  index: i + 1,
                  reorderIndex: i,
                  nextVideoUrl: _nextVideoUrl(filtered, i),
                  task: task,
                  role: widget.role,
                  videoPath: videoPath,
                  videoStatus: videoState.status,
                  downloadProgress: videoState.progress,
                  selectedDate: widget.selectedDate,
                  onRefresh: widget.onRefresh,
                  onShowVideoPlayer: (videoIndex) {
                    // ── MUHIM: faqat videoli tasklar va to'g'ri index ──────────
                    if (_taskVideos(task).isEmpty) return; // videosiz task

                    final allVideoPaths = _getVideoPaths(downloadProvider);
                    final videoTasks = _getVideoTasks();
                    final firstIndex = _getVideoIndex(task);

                    if (firstIndex < 0 || allVideoPaths.isEmpty) return;
                    // Bosilgan thumbnail — taskning nechanchi videosi
                    final startIndex = firstIndex + videoIndex;

                    widget.onShowVideoPlayer(
                      allVideoPaths,
                      startIndex,
                      videoTasks, // ← faqat videoli tasklar
                    );
                  },
                  onShareVideo: () => _shareTaskLink(task),
                  onTogglePin: () => tasksProvider.togglePin(task),
                  onEdit: widget.onEditTask == null
                      ? null
                      : () => widget.onEditTask!(task),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
