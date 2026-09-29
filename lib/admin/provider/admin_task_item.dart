import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/video_download_provider.dart';
import 'package:mone_task_app/admin/ui/audio_task_row.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
import 'package:provider/provider.dart';

const _weekDayShort = ['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'];

/// Vazifa turi + kunlari: "Har kuni", "Har hafta: Du, Ju", "Har oy: 5, 20".
String _scheduleLabel(TaskModel task) {
  final days = task.days ?? <int>[];
  switch (task.type) {
    case 2:
      final names = [
        for (final d in days)
          if (d >= 1 && d <= 7) tr(_weekDayShort[d - 1]),
      ];
      return names.isEmpty
          ? tr('Har hafta')
          : '${tr('Har hafta')}: ${names.join(', ')}';
    case 3:
      return days.isEmpty
          ? tr('Har oy')
          : '${tr('Har oy')}: ${days.join(', ')}';
    default:
      return tr('Har kuni');
  }
}

class AdminTaskListItem extends StatefulWidget {
  final int index;
  final TaskModel task;
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

class _AdminTaskListItemState extends State<AdminTaskListItem> {
  TaskModel get task => widget.task;

  bool get _hasVideo => task.videoUrl != null && task.videoUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _handleTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Sarlavha ───────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IndexBubble(index: widget.index),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        trData(task.task),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                  _buildShareButton(),
                ],
              ),
              SizedBox(height: AppSpacing.sm),

              // ── Meta: holat, tur, kim yubordi ─────────────────────────
              Padding(
                padding: EdgeInsets.only(left: 40, right: 8),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildStatusBadge(),
                    _MetaText(
                      icon: CupertinoIcons.repeat,
                      text: _scheduleLabel(task),
                    ),
                    if (task.submittedBy != null)
                      _MetaText(
                        icon: CupertinoIcons.person,
                        text: _submittedLabel(),
                      ),
                  ],
                ),
              ),
              SizedBox(height: AppSpacing.md),

              // ── Video + holat tugmalari ───────────────────────────────
              Padding(
                padding: EdgeInsets.only(left: 40, right: 8),
                child: Row(
                  children: [
                    Expanded(child: _buildVideoAction()),
                    SizedBox(width: AppSpacing.sm),
                    _buildStatusIndicator(),
                  ],
                ),
              ),

              // ── Ovozli izoh: yozish + yuborish + eshitish ────────────
              SizedBox(height: AppSpacing.sm),
              Padding(
                padding: EdgeInsets.only(left: 40, right: 8),
                child: AudioTaskRow.fromCheckerTask(
                  task: task,
                  selectedDate: widget.selectedDate,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _submittedLabel() {
    final name = displayName(task.submittedBy);
    final at = task.submittedAt?.toLocal();
    if (at == null) return name;
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '$name · $hh:$mm';
  }

  // ── Holat belgisi ─────────────────────────────────────────────────────────

  Widget _buildStatusBadge() {
    final status = task.status;
    if (status != null) return StatusBadge.forTask(status);
    if (_hasVideo) {
      return StatusBadge(
        label: tr("Ko'rilmagan"),
        color: AppColors.info,
        background: AppColors.infoSoft,
      );
    }
    return StatusBadge(
      label: tr('Video yuborilmagan'),
      color: AppColors.textSecondary,
      background: AppColors.surfaceMuted,
    );
  }

  // ── Asosiy amal: videoni ko'rish ──────────────────────────────────────────

  Widget _buildVideoAction() {
    if (!_hasVideo) {
      return Row(
        children: [
          Icon(
            Icons.videocam_off_rounded,
            size: 18,
            color: AppColors.textTertiary,
          ),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              tr("Video yo'q"),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
            ),
          ),
        ],
      );
    }

    final (Widget icon, String label) = switch (widget.videoStatus) {
      VideoStatus.downloading => (
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            value: widget.downloadProgress > 0 ? widget.downloadProgress : null,
            strokeWidth: 2,
          ),
        ),
        '${(widget.downloadProgress * 100).toInt()}%',
      ),
      VideoStatus.error => (
        Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
        tr("Ko'rish"),
      ),
      VideoStatus.notStarted => (
        Icon(CupertinoIcons.cloud_download, size: 18),
        tr("Ko'rish"),
      ),
      VideoStatus.cached => (
        Icon(CupertinoIcons.play_fill, size: 16),
        tr("Ko'rish"),
      ),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: widget.videoStatus == VideoStatus.error
            ? tr('Video yuklanmadi. Bosib qayta ochib koʻring.')
            : tr('Videoni koʻrish'),
        child: FilledButton.tonalIcon(
          onPressed: _handleTap,
          style: FilledButton.styleFrom(
            minimumSize: Size(0, 40),
            padding: EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
          icon: icon,
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  // ── Holat tugmalari (bajarildi / tekshiruvda / bajarilmagan) ──────────────

  Widget _buildStatusIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "Bajarildi" — video 50% ko'rilganda avtomatik qo'yiladi.
        _statusCircleButton(3, Icons.check_rounded, enabled: false),
        SizedBox(width: 6),
        _statusCircleButton(2, Icons.schedule_rounded, enabled: _hasVideo),
        SizedBox(width: 6),
        _statusCircleButton(1, Icons.close_rounded, enabled: _hasVideo),
      ],
    );
  }

  Widget _statusCircleButton(int level, IconData icon, {bool enabled = true}) {
    final currentStatus = task.status;
    final isActive = currentStatus == level;
    final color = statusColor(level);
    const double size = 34;

    return Tooltip(
      message: taskStatusLabel(level),
      child: InkResponse(
        radius: 22,
        onTap: enabled
            ? () async {
                if (currentStatus != level) {
                  final tasksProvider = context.read<AdminTasksProvider>();
                  final ok = await tasksProvider.updateTaskStatus(
                    task.taskId,
                    level,
                    widget.selectedDate,
                  );
                  if (!ok && mounted) {
                    showAppSnack(
                      context,
                      tr("Holatni o'zgartirib bo'lmadi. Qayta urinib ko'ring."),
                      type: SnackType.error,
                    );
                  }
                }
              }
            : null,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? color : statusSoftColor(level),
            border: Border.all(
              color: isActive
                  ? color
                  : color.withValues(alpha: enabled ? 0.45 : 0.2),
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive
                ? (AppThemeController.instance.isDark
                      ? AppColors.background
                      : Colors.white)
                : color.withValues(alpha: enabled ? 0.9 : 0.4),
          ),
        ),
      ),
    );
  }

  // ── Ulashish ──────────────────────────────────────────────────────────────

  Widget _buildShareButton() {
    if (!_hasVideo) return SizedBox(width: 8);
    final isWindows = Platform.isWindows;
    return IconButton(
      onPressed: widget.onShareVideo,
      tooltip: isWindows ? tr('Havolani nusxalash') : tr('Ulashish'),
      visualDensity: VisualDensity.compact,
      color: AppColors.textSecondary,
      icon: Icon(
        isWindows ? CupertinoIcons.doc_on_doc : CupertinoIcons.share,
        size: 20,
      ),
    );
  }

  // ── Bosilganda ────────────────────────────────────────────────────────────

  Future<void> _handleTap() async {
    if (_hasVideo) {
      widget.onShowVideoPlayer(task.videoUrl!);
    }
  }
}

class _IndexBubble extends StatelessWidget {
  const _IndexBubble({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.smAll,
      ),
      child: Text(
        '$index',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
