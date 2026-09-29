import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
import 'package:path_provider/path_provider.dart';

class VideoCacheManagerPage extends StatefulWidget {
  const VideoCacheManagerPage({super.key});

  @override
  State<VideoCacheManagerPage> createState() => _VideoCacheManagerPageState();
}

class _VideoCacheManagerPageState extends State<VideoCacheManagerPage> {
  bool _isLoading = true;
  bool _error = false;
  int _totalVideos = 0;
  double _totalSize = 0; // MB da
  List<VideoFileInfo> _videoFiles = [];

  @override
  void initState() {
    super.initState();
    _loadCacheInfo();
  }

  Future<void> _loadCacheInfo() async {
    setState(() {
      _isLoading = true;
      _error = false;
    });

    try {
      final directory = await getApplicationDocumentsDirectory();
      final videosDir = Directory('${directory.path}/videos');

      if (!await videosDir.exists()) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _totalVideos = 0;
          _totalSize = 0;
          _videoFiles = [];
        });
        return;
      }

      final files = videosDir.listSync();
      final videoFiles = <VideoFileInfo>[];
      double totalBytes = 0;

      for (var file in files) {
        if (file is File) {
          final stat = await file.stat();
          final sizeInMB = stat.size / (1024 * 1024);
          totalBytes += stat.size;

          videoFiles.add(
            VideoFileInfo(
              name: file.path.split(Platform.pathSeparator).last.split('/').last,
              path: file.path,
              size: sizeInMB,
              date: stat.modified,
            ),
          );
        }
      }

      // Sanaga ko'ra saralash (eng yangi birinchi)
      videoFiles.sort((a, b) => b.date.compareTo(a.date));

      if (!mounted) return;
      setState(() {
        _totalVideos = videoFiles.length;
        _totalSize = totalBytes / (1024 * 1024);
        _videoFiles = videoFiles;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Cache info yuklashda xatolik: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = true;
      });
    }
  }

  String _mb(double v) => '${v.toStringAsFixed(v >= 100 ? 0 : 1)} MB';

  Future<void> _clearAllCache() async {
    final confirm = await showConfirmDialog(
      context,
      title: tr('Keshni tozalash'),
      message:
          '$_totalVideos ${tr('ta video')} (${_mb(_totalSize)}) ${tr("telefondan o'chiriladi. Kerak bo'lsa, ular qayta yuklab olinadi.")}',
      confirmLabel: tr('Ha, tozalash'),
      destructive: true,
    );

    if (!confirm) return;

    setState(() => _isLoading = true);

    try {
      final directory = await getApplicationDocumentsDirectory();
      final videosDir = Directory('${directory.path}/videos');

      if (await videosDir.exists()) {
        await videosDir.delete(recursive: true);
        await videosDir.create();
      }

      if (mounted) {
        showAppSnack(context, tr('Kesh tozalandi'), type: SnackType.success);
      }

      await _loadCacheInfo();
    } catch (e) {
      debugPrint('Cache tozalashda xatolik: $e');
      if (mounted) {
        showAppSnack(context, '${tr('Xatolik')}: $e', type: SnackType.error);
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteVideo(VideoFileInfo video) async {
    final confirm = await showConfirmDialog(
      context,
      title: tr("Videoni o'chirish"),
      message: '${video.name} — ${tr('Ishonchingiz komilmi?')}',
      confirmLabel: tr("Ha, o'chirish"),
      destructive: true,
    );

    if (!confirm) return;

    try {
      final file = File(video.path);
      if (await file.exists()) {
        await file.delete();
      }

      if (mounted) {
        showAppSnack(
          context,
          tr("Video o'chirildi"),
          type: SnackType.success,
        );
      }

      await _loadCacheInfo();
    } catch (e) {
      debugPrint('Video o\'chirishda xatolik: $e');
      if (mounted) {
        showAppSnack(context, '${tr('Xatolik')}: $e', type: SnackType.error);
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diffDays = today.difference(day).inDays;
    final hm =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    if (diffDays == 0) {
      return '${tr('Bugun')}, $hm';
    } else if (diffDays == 1) {
      return '${tr('Kecha')}, $hm';
    } else if (diffDays < 7) {
      return '$diffDays ${tr('kun oldin')}';
    } else {
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Video kesh')),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadCacheInfo,
            icon: Icon(Icons.refresh_rounded),
            tooltip: tr('Yangilash'),
          ),
        ],
      ),
      body: _isLoading
          ? AppLoader()
          : _error
          ? AppErrorState(
              message: tr("Video fayllarni o'qib bo'lmadi."),
              onRetry: _loadCacheInfo,
            )
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 720),
                child: RefreshIndicator(
                  onRefresh: _loadCacheInfo,
                  child: _buildList(context),
                ),
              ),
            ),
    );
  }

  Widget _buildList(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _summaryCard(context),
        if (_totalVideos == 0)
          Padding(
            padding: EdgeInsets.only(top: 24),
            child: AppEmptyState(
              icon: Icons.video_library_outlined,
              title: tr("Keshda video yo'q"),
              message: tr(
                "Ko'rilgan videolar shu yerda saqlanadi va keyingi safar tezroq ochiladi.",
              ),
            ),
          )
        else ...[
          AppSectionHeader(
            tr('Saqlangan videolar'),
            trailing: Text(
              '$_totalVideos',
              style: t.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          ..._videoFiles.map(
            (video) => Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: EdgeInsets.fromLTRB(12, 4, 4, 4),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: Icon(
                      Icons.play_circle_outline_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(
                    video.name,
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_formatDate(video.date)} · ${_mb(video.size)}',
                    style: t.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    onPressed: () => _deleteVideo(video),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.danger,
                    ),
                    tooltip: tr("O'chirish"),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _summaryCard(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.videocam_outlined,
                    label: tr('Videolar'),
                    value: '$_totalVideos ${tr('ta')}',
                  ),
                ),
                Container(width: 1, height: 44, color: AppColors.divider),
                Expanded(
                  child: _StatCard(
                    icon: Icons.sd_storage_outlined,
                    label: tr('Hajmi'),
                    value: _mb(_totalSize),
                  ),
                ),
              ],
            ),
            if (_totalVideos > 0) ...[
              SizedBox(height: AppSpacing.md),
              Text(
                '${tr("Bitta video o'rtacha")}: ${_mb(_totalSize / _totalVideos)}',
                style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _clearAllCache,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.danger),
                ),
                icon: Icon(Icons.cleaning_services_outlined, size: 20),
                label: Text(tr('Keshni tozalash')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 26),
        SizedBox(height: 6),
        Text(
          value,
          style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 2),
        Text(
          label,
          style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class VideoFileInfo {
  final String name;
  final String path;
  final double size; // MB da
  final DateTime date;

  VideoFileInfo({
    required this.name,
    required this.path,
    required this.size,
    required this.date,
  });
}
