import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/ui/dialog.dart';
import 'package:mone_task_app/admin/ui/edit_task_ui.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/utils/get_color.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ─── Global static cache — tab o'tganda yo'qolmaydi ─────────────────────────

class VideoDownloadCache {
  VideoDownloadCache._();

  /// url → local file path (to'liq yuklangan)
  static final Map<String, String> cachedVideos = {};

  /// url → progress 0.0..1.0 (yuklanayotgan)
  static final Map<String, double> downloadingVideos = {};

  /// Sequential download hozir ishlayaptimi
  static bool _sequenceRunning = false;

  static bool isCached(String url) => cachedVideos.containsKey(url);
  static bool isDownloading(String url) => downloadingVideos.containsKey(url);
  static double progress(String url) => downloadingVideos[url] ?? 0.0;
}

// ─────────────────────────────────────────────────────────────────────────────

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
  late Timer _uiRefreshTimer;

  @override
  void initState() {
    super.initState();

    // Cache o'zgarishlarini UI ga aks ettirish uchun har 400ms rebuild
    _uiRefreshTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() {});
    });

    _ensureVideoDirExists();
    _startSequentialDownloadIfNeeded();
  }

  @override
  void dispose() {
    _uiRefreshTimer.cancel();
    super.dispose();
  }

  Future<void> _ensureVideoDirExists() async {
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

  /// Faqat bir marta ishga tushadigan sequential download
  void _startSequentialDownloadIfNeeded() {
    if (VideoDownloadCache._sequenceRunning) return;

    final filteredTasks = widget.tasks
        .where((t) => t.filialId == widget.filialId)
        .toList();

    final videoUrls = filteredTasks
        .where((t) => t.videoUrl != null && t.videoUrl!.isNotEmpty)
        .map((t) => _getFullUrl(t.videoUrl!))
        .toList();

    // Tartibni saqlagan holda dublikatlarni olib tashlaymiz
    final seen = <String>{};
    final uniqueUrls = videoUrls.where((url) => seen.add(url)).toList();

    // Hali yuklanmagan yoki yuklanmayotgan URLlar
    final pending = uniqueUrls
        .where(
          (url) =>
              !VideoDownloadCache.isCached(url) &&
              !VideoDownloadCache.isDownloading(url),
        )
        .toList();

    if (pending.isEmpty) return;

    VideoDownloadCache._sequenceRunning = true;
    _runSequence(pending);
  }

  Future<void> _runSequence(List<String> urls) async {
    for (final url in urls) {
      await _downloadVideo(url);
    }
    VideoDownloadCache._sequenceRunning = false;
  }

  /// Bitta videoni yuklab global cache ga yozadi
  Future<void> _downloadVideo(String videoUrl) async {
    if (VideoDownloadCache.isCached(videoUrl)) return;

    // Boshqa joydan allaqachon yuklanayotgan bo'lsa, tugashini kutamiz
    if (VideoDownloadCache.isDownloading(videoUrl)) {
      while (VideoDownloadCache.isDownloading(videoUrl)) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      return;
    }

    VideoDownloadCache.downloadingVideos[videoUrl] = 0.0;

    try {
      final localPath = await _getLocalFilePath(videoUrl);
      final file = File(localPath);

      // Diskda to'liq fayl mavjudmi?
      if (await file.exists() && await file.length() > 0) {
        try {
          final dio = Dio();
          final head = await dio.head(videoUrl);
          final serverSize = int.tryParse(
            head.headers.value('content-length') ?? '',
          );
          final localSize = await file.length();

          if (serverSize == null || localSize >= serverSize) {
            VideoDownloadCache.cachedVideos[videoUrl] = localPath;
            VideoDownloadCache.downloadingVideos.remove(videoUrl);
            return;
          } else {
            await file.delete(); // Yarim yuklangan — o'chiramiz
          }
        } catch (_) {
          VideoDownloadCache.cachedVideos[videoUrl] = localPath;
          VideoDownloadCache.downloadingVideos.remove(videoUrl);
          return;
        }
      }

      final tempPath = '$localPath.tmp';
      final tempFile = File(tempPath);

      final dio = Dio();
      await dio.download(
        videoUrl,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            VideoDownloadCache.downloadingVideos[videoUrl] = received / total;
          }
        },
      );

      if (await tempFile.exists() && await tempFile.length() > 0) {
        try {
          final head = await dio.head(videoUrl);
          final serverSize = int.tryParse(
            head.headers.value('content-length') ?? '',
          );
          final downloadedSize = await tempFile.length();

          if (serverSize != null && downloadedSize < serverSize) {
            await tempFile.delete();
            VideoDownloadCache.downloadingVideos.remove(videoUrl);
            return;
          }
        } catch (_) {}

        await tempFile.rename(localPath);
        VideoDownloadCache.cachedVideos[videoUrl] = localPath;
        VideoDownloadCache.downloadingVideos.remove(videoUrl);
      } else {
        if (await tempFile.exists()) await tempFile.delete();
        VideoDownloadCache.downloadingVideos.remove(videoUrl);
      }
    } catch (e) {
      try {
        final localPath = await _getLocalFilePath(videoUrl);
        final tempFile = File('$localPath.tmp');
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      VideoDownloadCache.downloadingVideos.remove(videoUrl);
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
          return VideoDownloadCache.cachedVideos[fullUrl] ?? fullUrl;
        })
        .toList();
  }

  Future<void> _shareVideo(CheckerCheckTaskModel task) async {
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

      final fullUrl = _getFullUrl(videoUrl);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              const Center(child: CircularProgressIndicator.adaptive()),
        );
      }

      String localPath;

      if (VideoDownloadCache.isCached(fullUrl)) {
        localPath = VideoDownloadCache.cachedVideos[fullUrl]!;
      } else {
        localPath = await _getLocalFilePath(fullUrl);
        final file = File(localPath);
        if (!await file.exists() || await file.length() == 0) {
          final dio = Dio();
          await dio.download(fullUrl, localPath);
        }
        VideoDownloadCache.cachedVideos[fullUrl] = localPath;
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
              fullVideoUrl != null && VideoDownloadCache.isCached(fullVideoUrl);
          final bool isDownloading =
              fullVideoUrl != null &&
              VideoDownloadCache.isDownloading(fullVideoUrl);
          final double downloadProgress = fullVideoUrl != null
              ? VideoDownloadCache.progress(fullVideoUrl)
              : 0.0;

          String? videoPath;
          if (fullVideoUrl != null) {
            videoPath = isVideoCached
                ? VideoDownloadCache.cachedVideos[fullVideoUrl]
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
            downloadProgress: downloadProgress,
            selectedDate: widget.selectedDate,
            onRefresh: widget.onRefresh,
            onShowVideoPlayer: (path) {
              final allPaths = _getAllVideoPaths();
              final startIndex = videoIndex >= 0 ? videoIndex : 0;
              widget.onShowVideoPlayer(allPaths, startIndex, filtered);
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
    required this.isVideoCached,
    required this.isDownloading,
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

  // ── Default layout (telefon + planşet portrait) ───────────────────────────

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

  // ── Planşet landscape layout ──────────────────────────────────────────────

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
              // Task ma'lumotlari — kenglikning 65%
              Expanded(
                flex: 65,
                child: _buildTaskInfo(context, showBadge: false),
              ),
              const SizedBox(width: 16),
              // Video badge + share — o'ng tomonda, kichik joy
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

  // ── Shared widgets ────────────────────────────────────────────────────────

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
            if (task.videoUrl != null && task.videoUrl!.isNotEmpty)
              buildStatusIndicator(task.status),
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
    if (widget.isVideoCached) {
      // ✅ To'liq — yashil + 100%
      return Text(
        '',
        style: TextStyle(
          fontSize: 16,
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    if (widget.isDownloading) {
      final percent = (widget.downloadProgress * 100).toInt();
      return Row(
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
              backgroundColor: Colors.black12,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$percent%  ',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    // ☁ Hali boshlanmagan (navbatda)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.cloud_download, size: 16, color: Colors.white),
    );
  }

  // ── Handlers ──────────────────────────────────────────────────────────────

  Future<void> _handleLongPress() async {
    final isDelete = await NativeDialog.showDeleteDialog();
    if (isDelete) {
      await AdminTaskService().deleteTask(task.taskId);
      widget.onRefresh();
    }
  }

  Future<void> _handleDoubleTap() async {
    context.push(EditTaskUi(task: task));
  }

  Future<void> _handleTap() async {
    if (widget.videoPath != null) {
      widget.onShowVideoPlayer(widget.videoPath!);
    }
  }

  Widget buildStatusIndicator(int status) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _statusCircleButton(1, status, Colors.red),
        const SizedBox(width: 6),
        _statusCircleButton(2, status, Colors.orange),
        const SizedBox(width: 6),
        _statusCircleButton(3, status, Colors.green),
      ],
    );
  }

  Widget _statusCircleButton(int level, int currentStatus, Color activeColor) {
    final bool isActive = currentStatus >= level;

    return GestureDetector(
      onTap: () async {
        if (currentStatus != level) {
          final bool isSuccess = await AdminTaskService().updateTaskStatus(
            task.taskId,
            level,
            widget.selectedDate,
            null,
          );
          if (isSuccess && mounted) {
            setState(() => task.status = level);
          }
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 10),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? activeColor : Colors.grey.shade300,
          border: Border.all(
            color: isActive ? activeColor : Colors.grey,
            width: 2,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: activeColor.withOpacity(0.4), blurRadius: 4)]
              : [],
        ),
        child: isActive
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      ),
    );
  }
}
