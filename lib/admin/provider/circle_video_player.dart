import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/provider/video_player_provider.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class CircleVideoPlayer extends StatelessWidget {
  final List<CheckerCheckTaskModel> title;
  final List<String> videoUrls;
  final int initialIndex;
  final VoidCallback? onHalfWatched;

  const CircleVideoPlayer({
    required this.title,
    super.key,
    required this.videoUrls,
    this.initialIndex = 0,
    this.onHalfWatched,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => VideoPlayerProvider(
        videoUrls: videoUrls,
        initialIndex: initialIndex,
        onHalfWatched: onHalfWatched,
      ),
      child: _CircleVideoPlayerBody(tasks: title),
    );
  }
}

class _CircleVideoPlayerBody extends StatefulWidget {
  final List<CheckerCheckTaskModel> tasks;

  const _CircleVideoPlayerBody({required this.tasks});

  @override
  State<_CircleVideoPlayerBody> createState() => _CircleVideoPlayerBodyState();
}

class _CircleVideoPlayerBodyState extends State<_CircleVideoPlayerBody>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VideoPlayerProvider>();
    final size = MediaQuery.of(context).size;
    final bool isTablet = size.shortestSide >= 600;
    final double circleSize = isTablet
        ? size.shortestSide * 0.70
        : size.width * 0.85;

    final double arcRadius = circleSize / 2 + 14;
    final double arcStroke = 6.0;
    final double arcBoxSize = (arcRadius + arcStroke) * 2;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Title ──────────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 50,
            right: 50,
            child: Text(
              widget.tasks.isNotEmpty
                  ? widget.tasks[provider.currentIndex].task
                  : "Видео",
              style: const TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // ── Background tap to close ────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(color: Colors.transparent),
            ),
          ),

          // ── Main content ───────────────────────────────────────────────
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildVideoCircle(
                  context,
                  provider,
                  arcBoxSize,
                  arcRadius,
                  arcStroke,
                  circleSize,
                ),
                if (provider.isInitialized && !provider.hasError) ...[
                  const SizedBox(height: 16),
                  _buildControlPanel(provider, circleSize),
                ],
              ],
            ),
          ),

          // ── Close button ───────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),

          // ── Mute button ────────────────────────────────────────────────
          if (provider.isInitialized && !provider.hasError)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: GestureDetector(
                onTap: provider.toggleMute,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: Icon(
                    provider.isMuted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoCircle(
    BuildContext context,
    VideoPlayerProvider provider,
    double arcBoxSize,
    double arcRadius,
    double arcStroke,
    double circleSize,
  ) {
    return SizedBox(
      width: arcBoxSize,
      height: arcBoxSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background arc
          CustomPaint(
            size: Size(arcBoxSize, arcBoxSize),
            painter: _CircularProgressPainter(
              progress: 1.0,
              color: Colors.white24,
              strokeWidth: arcStroke,
              radius: arcRadius,
            ),
          ),
          // Progress arc
          CustomPaint(
            size: Size(arcBoxSize, arcBoxSize),
            painter: _CircularProgressPainter(
              progress: provider.progress,
              color: Colors.blue,
              strokeWidth: arcStroke,
              radius: arcRadius,
              showDot: true,
            ),
          ),
          // Seek gesture on arc
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: provider.isInitialized
                ? (d) =>
                      provider.seekFromCircleTouch(d.localPosition, arcBoxSize)
                : null,
            onPanUpdate: provider.isInitialized
                ? (d) =>
                      provider.seekFromCircleTouch(d.localPosition, arcBoxSize)
                : null,
            onTapDown: provider.isInitialized
                ? (d) =>
                      provider.seekFromCircleTouch(d.localPosition, arcBoxSize)
                : null,
            child: SizedBox(width: arcBoxSize, height: arcBoxSize),
          ),
          // Video circle
          ScaleTransition(
            scale: Tween(begin: 0.8, end: 1.0).animate(
              CurvedAnimation(
                parent: _animationController,
                curve: Curves.easeOut,
              ),
            ),
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity != null) {
                  if (details.primaryVelocity! < -300) provider.goToNext();
                  if (details.primaryVelocity! > 300) provider.goToPrev();
                }
              },
              child: Container(
                width: circleSize,
                height: circleSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (provider.isInitialized &&
                          !provider.hasError &&
                          provider.controller != null)
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: provider.controller!.value.size.width,
                            height: provider.controller!.value.size.height,
                            child: VideoPlayer(provider.controller!),
                          ),
                        ),
                      if (!provider.isInitialized && !provider.hasError)
                        const Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      if (provider.hasError)
                        _buildErrorOverlay(provider.errorMessage),
                      if (provider.isInitialized && !provider.isPlaying)
                        Container(
                          color: Colors.black26,
                          child: const Center(
                            child: Icon(
                              Icons.play_arrow,
                              size: 70,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorOverlay(String? errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text(
              "Video yuklanmadi",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                errorMessage,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel(VideoPlayerProvider provider, double circleSize) {
    return Container(
      width: circleSize,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTimeRow(provider),
          const SizedBox(height: 4),
          _buildControls(provider),
        ],
      ),
    );
  }

  Widget _buildTimeRow(VideoPlayerProvider provider) {
    final task = widget.tasks.isNotEmpty
        ? widget.tasks[provider.currentIndex]
        : null;

    return Row(
      children: [
        Text(
          "${task?.date} ${task?.submittedAt?.toLocal().hour.toString().padLeft(2, '0') ?? '00'}:${task?.submittedAt?.toLocal().minute.toString().padLeft(2, '0') ?? '00'}",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Spacer(),
        Text(
          provider.formatDuration(provider.duration),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildControls(VideoPlayerProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Spacer(),
        IconButton(
          onPressed: provider.hasPrev ? provider.goToPrev : null,
          icon: Icon(
            Icons.skip_previous_rounded,
            color: provider.hasPrev ? Colors.white : Colors.white30,
            size: 32,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: provider.togglePlayPause,
          icon: Icon(
            provider.isPlaying
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_filled_rounded,
            color: Colors.white,
            size: 44,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: provider.hasNext ? provider.goToNext : null,
          icon: Icon(
            Icons.skip_next_rounded,
            color: provider.hasNext ? Colors.white : Colors.white30,
            size: 32,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: provider.cycleSpeed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: provider.playbackSpeed != 1.0
                  ? Colors.blue.withOpacity(0.8)
                  : Colors.white24,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              provider.speedLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Spacer(),
        buildStatusIndicator(
          widget.tasks[provider.currentIndex].status,
          widget.tasks[provider.currentIndex],
        ),
      ],
    );
  }

  Widget buildStatusIndicator(int status, CheckerCheckTaskModel task) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // _statusCircleButton(1, status, Colors.red, task.taskId, task.date!),
        // const SizedBox(width: 25),
        // _statusCircleButton(2, status, Colors.orange, task.taskId, task.date!),
        // const SizedBox(width: 15),
        // _statusCircleButton(3, status, Colors.green, task.taskId, task.date!),
      ],
    );
  }

  Widget _statusCircleButton(
    int level,
    int currentStatus,
    Color activeColor,
    int taskId,
    String selectedDate,
  ) {
    final bool isActive = currentStatus >= level;

    return GestureDetector(
      onTap: () async {
        if (currentStatus != level) {
          final bool isSuccess = await AdminTaskService().updateTaskStatus(
            taskId,
            level,
            null,
            selectedDate,
          );
          if (isSuccess && mounted) {
            // setState(() => task.status = level);
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

// ─── Circular progress painter ──────────────────────────────────────────────

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final double radius;
  final bool showDot;

  const _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.radius,
    this.showDot = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );

    if (showDot && progress > 0) {
      final dotAngle = startAngle + sweepAngle;
      final dotX = center.dx + radius * math.cos(dotAngle);
      final dotY = center.dy + radius * math.sin(dotAngle);

      canvas.drawCircle(
        Offset(dotX, dotY),
        strokeWidth + 3,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(dotX, dotY),
        strokeWidth,
        Paint()..color = Colors.blue,
      );
    }
  }

  @override
  bool shouldRepaint(_CircularProgressPainter old) =>
      old.progress != progress || old.color != color;
}
