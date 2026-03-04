import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/video_download_provider.dart';
import 'package:mone_task_app/admin/ui/dialog.dart';
import 'package:mone_task_app/admin/ui/edit_task_ui.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/utils/get_color.dart';
import 'package:provider/provider.dart';

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
                getTypeName(task.type),
                style: const TextStyle(fontSize: 12, color: Colors.black),
              ),
            ),
            if (showBadge && task.videoUrl != null && task.videoUrl!.isNotEmpty)
              _buildVideoStatusBadge(),
            const SizedBox(width: 8),
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
    switch (widget.videoStatus) {
      case VideoStatus.cached:
        return const SizedBox();

      case VideoStatus.downloading:
        final percent = (widget.downloadProgress * 100).toInt();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$percent%',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  value: widget.downloadProgress > 0
                      ? widget.downloadProgress
                      : null,
                  strokeWidth: 2,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.black),
                  backgroundColor: Colors.black12,
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

  // ── Status indicator ──────────────────────────────────────────────────────

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
          final tasksProvider = context.read<AdminTasksProvider>();
          final bool isSuccess = await tasksProvider.updateTaskStatus(
            task.taskId,
            level,
            widget.selectedDate,
          );
          if (isSuccess && mounted) {
            setState(() => task.status = level);
          }
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
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

  // ── Handlers ──────────────────────────────────────────────────────────────

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
    widget.onShowVideoPlayer(widget.videoPath!);
  }
}
