import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/ui/audio_task_row.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/checker/ui/player2.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
import 'package:mone_task_app/core/utils/share_helper.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class TaskListWidget extends StatefulWidget {
  final List<TaskModel> tasks;
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

  void _shareTaskLink(TaskModel task) {
    final link = 'https://taskapi.monebakeryuz.uz/task/${task.date}/${task.taskId}';
    shareTaskLink(title: task.task, link: link, context: context);
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
      return RefreshIndicator(
        onRefresh: () async => widget.onRefresh(),
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: c.maxHeight,
              child: AppEmptyState(
                icon: Icons.task_alt_rounded,
                title: tr('Bu filialda vazifa yoʻq'),
                message: tr(
                  'Boshqa filial yoki sanani tanlang. Yangilash uchun pastga torting.',
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      child: ListView.builder(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
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
            onShareVideo: () => _shareTaskLink(filtered[i]),
            getVideoPath: _getVideoPath,
          );
        },
      ),
    );
  }
}

class TaskListItem extends StatefulWidget {
  final TaskModel task;
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
  late TaskModel task;

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

  bool get _hasVideo => task.videoUrl != null && task.videoUrl!.isNotEmpty;

  /// Vazifa takrorlanishi: Har kuni / Har hafta: Du, Se / Har oy: 1, 15.
  String _typeLabel() {
    final days = task.days ?? <int>[];
    switch (task.type) {
      case 1:
        return tr('Har kuni');
      case 2:
        final names = days.map(_weekdayShort).join(', ');
        return names.isEmpty ? tr('Har hafta') : '${tr('Har hafta')}: $names';
      case 3:
        return days.isEmpty
            ? tr('Har oy')
            : '${tr('Har oy')}: ${days.join(', ')}';
      default:
        return '';
    }
  }

  static String _weekdayShort(int d) => switch (d) {
    1 => tr('Du'),
    2 => tr('Se'),
    3 => tr('Ch'),
    4 => tr('Pa'),
    5 => tr('Ju'),
    6 => tr('Sh'),
    7 => tr('Ya'),
    _ => '--',
  };

  String? _submittedLine() {
    if (task.submittedBy == null) return null;
    final at = task.submittedAt?.toLocal();
    final time = at == null
        ? ''
        : ' · ${at.hour.toString().padLeft(2, '0')}:'
              '${at.minute.toString().padLeft(2, '0')}';
    return '${trData(task.submittedBy)}$time';
  }

  Future<void> _resetStatus() async {
    if (!_hasVideo) return;
    final ok = await showConfirmDialog(
      context,
      title: tr('Holatni qaytarasizmi?'),
      message: tr(
        'Vazifa «Bajarilmagan» holatiga qaytariladi. Ishonchingiz komilmi?',
      ),
      confirmLabel: tr('Ha, qaytarish'),
      destructive: true,
    );
    if (!ok) return;
    final bool isDelete = await TaskViewService().updateTaskStatus(
      task.taskId,
      1,
      widget.selectedDate,
      null,
    );
    if (!mounted) return;
    if (isDelete) {
      showAppSnack(context, tr('Holat yangilandi'), type: SnackType.success);
      widget.onRefresh();
    } else {
      showAppSnack(
        context,
        tr('Holatni oʻzgartirib boʻlmadi. Qayta urinib koʻring.'),
        type: SnackType.error,
      );
    }
  }

  void _openVideo() {
    if (!_hasVideo) {
      showAppSnack(context, tr('Video yoʻq'));
      return;
    }
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
              final bool isSuccess = await TaskViewService().updateTaskStatus(
                task.taskId,
                3,
                widget.selectedDate,
                null,
              );
              if (isSuccess && mounted) {
                setState(() => task.status = 3);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _videoBadge() {
    final (IconData icon, Color color, Color bg, String tip) =
        widget.isVideoCached
        ? (
            Icons.download_done_rounded,
            AppColors.success,
            AppColors.successSoft,
            tr('Video yuklab olindi'),
          )
        : widget.isDownloading
        ? (
            Icons.downloading_rounded,
            AppColors.warning,
            AppColors.warningSoft,
            tr('Video yuklanmoqda...'),
          )
        : (
            Icons.cloud_outlined,
            AppColors.info,
            AppColors.infoSoft,
            tr('Video serverda'),
          );
    return Tooltip(
      message: tip,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: widget.isDownloading
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.warning,
                ),
              )
            : Icon(icon, size: 18, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final submitted = _submittedLine();
    final typeLabel = _typeLabel();

    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onLongPress: _resetStatus,
          onTap: _openVideo,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Asosiy qator: info + tugmalar ─────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${widget.index + 1}. ${trData(task.task)}",
                            style: t.titleSmall?.copyWith(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 6),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusBadge.forTask(task.status ?? 1),
                              if (typeLabel.isNotEmpty)
                                Text(
                                  typeLabel,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                          if (submitted != null) ...[
                            SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.person_outline_rounded,
                                  size: 15,
                                  color: AppColors.textTertiary,
                                ),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    submitted,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_hasVideo) ...[
                      SizedBox(width: AppSpacing.sm),
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: _videoBadge(),
                      ),
                      IconButton(
                        tooltip: Platform.isWindows
                            ? tr('Havolani nusxalash')
                            : tr('Ulashish'),
                        onPressed: widget.onShareVideo,
                        color: AppColors.textSecondary,
                        icon: Icon(
                          Platform.isWindows
                              ? CupertinoIcons.doc_on_doc
                              : CupertinoIcons.share,
                          size: 20,
                        ),
                      ),
                    ],
                  ],
                ),

                // ── Audio yozish / tinglash (video bo'lsa chiqadi) ─────────
                AudioTaskRow.fromCheckerTask(
                  task: task,
                  selectedDate: widget.selectedDate,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
