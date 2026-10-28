import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/video_download_provider.dart';
import 'package:mone_task_app/admin/ui/audio_task_row.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/shared/widgets/guide_video_dialog.dart';
import 'package:mone_task_app/shared/widgets/status_permission.dart';
import 'package:mone_task_app/shared/widgets/task_video_strip.dart';
import 'package:mone_task_app/utils/get_color.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

class AdminTaskListItem extends StatelessWidget {
  final int index;
  final TaskModel task;
  final String? videoPath;
  final VideoStatus videoStatus;
  final double downloadProgress;
  final DateTime selectedDate;
  final String role;
  final VoidCallback onRefresh;

  /// [videoIndex] — taskning nechanchi videosi bosilgani
  final void Function(int videoIndex) onShowVideoPlayer;
  final VoidCallback onShareVideo;

  /// ReorderableListView ichidagi o'rni — sarlavhani bosib turib sudrash uchun
  final int? reorderIndex;

  /// Keyingi videoli vazifaning birinchi videosi (avtomatik davom etish uchun)
  final String? nextVideoUrl;

  /// Kartaning istalgan joyini ikki marta bosish — «Все задачи» da tahrirlash
  final VoidCallback? onEdit;

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
    this.reorderIndex,
    this.nextVideoUrl,
    this.onEdit,
  });

  bool get _hasVideo => task.hasAnyVideo;

  List<String> get _videos => task.allVideos;

  /// Kartaning chap chizig'i — joriy holat rangi
  Color get _accentColor {
    switch (task.status) {
      case 3:
        return Colors.green;
      case 2:
        return Colors.orange;
      case 1:
        return Colors.red;
    }
    if (task.videosComplete) return const Color(0xFF2563EB);
    return _hasVideo ? Colors.orange.shade200 : const Color(0xFFD1D5DB);
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return _DoubleTapArea(
      onDoubleTap: onEdit,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEDEEF1)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        // Chap rangli chiziq Positioned bilan — TaskVideoStrip ichidagi
        // LayoutBuilder IntrinsicHeight bilan ishlamaydi
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(color: _accentColor),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sarlavha qismini bosib turib sudrash — pastdagi ovoz yozish
                  // va videoni uzoq bosish bilan to'qnashmaydi
                  _dragArea(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(context, isTablet),
                        const SizedBox(height: 8),
                        _buildMeta(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TaskVideoStrip(
                    videoUrls: _videos,
                    slotCount: task.videoCount,
                    onOpenVideo: onShowVideoPlayer,
                    nextVideoUrl: nextVideoUrl,
                  ),
                  const SizedBox(height: 10),
                  AudioTaskRow.fromCheckerTask(
                    task: task,
                    selectedDate: selectedDate,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dragArea(Widget child) {
    final i = reorderIndex;
    if (i == null) return child;
    return ReorderableDelayedDragStartListener(index: i, child: child);
  }

  // ── Header: raqam + nom + status ──────────────────────────────────────────

  Widget _buildHeader(BuildContext context, bool isTablet) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.only(top: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4B5563),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            task.task,
            style: TextStyle(
              fontSize: isTablet ? 18 : 15.5,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: const Color(0xFF111827),
            ),
          ),
        ),
        // ⓘ — namuna video; yo'q bo'lsa super admin yuklay oladi
        GuideInfoButton(
          task: task,
          canUpload: role == 'super_admin',
          onUploaded: onRefresh,
          adminStyle: true,
        ),
        _StatusButtons(
          task: task,
          selectedDate: selectedDate,
          isTablet: isTablet,
        ),
      ],
    );
  }

  // ── Meta: tur, kim yubordi, videolar soni, yuklanish holati ───────────────

  Widget _buildMeta() {
    final submitted = task.submittedBy != null
        ? "${task.submittedBy} · "
              "${task.submittedAt?.toLocal().hour.toString().padLeft(2, '0')}:"
              "${task.submittedAt?.toLocal().minute.toString().padLeft(2, '0')}"
        : null;
    final slots = task.videoCount > _videos.length
        ? task.videoCount
        : _videos.length;

    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chip(
                Icons.repeat_rounded,
                getTypeName(task.type).replaceAll(':', '').trim(),
              ),
              // Vazifa kimga biriktirilgan (Эрталабги / Кечкурунгги Админ ...)
              if (task.category.isNotEmpty)
                _chip(
                  _categoryIcon(task.category),
                  task.category,
                  color: _categoryColor(task.category),
                ),
              if (slots > 1)
                _chip(
                  Icons.videocam_outlined,
                  task.videosComplete || !_hasVideo
                      ? "${_videos.length}/$slots"
                      : "${_videos.length}/$slots · не все видео",
                  color: task.videosComplete
                      ? Colors.green
                      : _hasVideo
                      ? Colors.orange
                      : const Color(0xFF2563EB),
                ),
              if (submitted != null) _chip(Icons.person_outline, submitted),
              if (_hasVideo) _buildDownloadBadge(),
            ],
          ),
        ),
        if (_hasVideo)
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 18,
              color: const Color(0xFF6B7280),
              onPressed: onShareVideo,
              icon: Icon(
                Platform.isWindows
                    ? CupertinoIcons.doc_on_doc
                    : CupertinoIcons.share,
              ),
            ),
          ),
      ],
    );
  }

  static IconData _categoryIcon(String category) {
    final c = category.toLowerCase();
    if (c.contains('эрталаб')) return Icons.wb_sunny_outlined;
    if (c.contains('кеч')) return Icons.nightlight_outlined;
    return Icons.badge_outlined;
  }

  static Color _categoryColor(String category) {
    final c = category.toLowerCase();
    if (c.contains('эрталаб')) return const Color(0xFFD97706);
    if (c.contains('кеч')) return const Color(0xFF4F46E5);
    return const Color(0xFF0D9488);
  }

  Widget _chip(IconData icon, String text, {Color? color}) {
    final c = color ?? const Color(0xFF6B7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color == null
            ? const Color(0xFFF3F4F6)
            : c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadBadge() {
    switch (videoStatus) {
      case VideoStatus.cached:
        return const SizedBox.shrink();
      case VideoStatus.downloading:
        return _chip(
          Icons.downloading_rounded,
          '${(downloadProgress * 100).toInt()}%',
          color: const Color(0xFF2563EB),
        );
      case VideoStatus.error:
        // Bosilsa — qayta yuklab ko'radi
        return Builder(
          builder: (context) => GestureDetector(
            onTap: () {
              final url = task.videoUrl;
              if (url == null || url.isEmpty) return;
              final provider = context.read<VideoDownloadProvider>();
              provider.retry(provider.getFullUrl(url));
            },
            child: _chip(Icons.refresh_rounded, 'Ошибка', color: Colors.red),
          ),
        );
      case VideoStatus.notStarted:
        return _chip(
          Icons.cloud_download_outlined,
          'Загрузка',
          color: const Color(0xFF2563EB),
        );
    }
  }
}

// ── Status tugmalari: yashil / sariq / qizil ───────────────────────────────

class _StatusButtons extends StatefulWidget {
  final TaskModel task;
  final DateTime selectedDate;
  final bool isTablet;

  const _StatusButtons({
    required this.task,
    required this.selectedDate,
    required this.isTablet,
  });

  @override
  State<_StatusButtons> createState() => _StatusButtonsState();
}

/// Sariq «Р» / qizil «А» doirasini bosib turish — ovoz yoziladi va
/// qo'yib yuborilganda yuboriladi (status serverda rolga qarab qo'yiladi).
/// Qisqa bosish — avvalgidek faqat status o'zgaradi.
class _StatusButtonsState extends State<_StatusButtons> {
  final AudioRecorder _recorder = AudioRecorder();
  int? _holdingLevel;
  bool _isRecording = false;
  bool _isSending = false;
  bool _cancelled = false;
  bool _pressing = false; // barmoq hali doirada
  int _recordSeconds = 0;
  Timer? _recordTimer;

  TaskModel get task => widget.task;

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording(int level) async {
    if (_isRecording || _isSending) return;
    if (!checkStatusPermission(context, level)) return;
    _pressing = true;

    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Доступ к микрофону не предоставлен')),
        );
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${task.taskId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: path,
    );
    // Mikrofon ochilguncha barmoq qo'yib yuborilgan — yozuvni tashlaymiz
    if (!_pressing || !mounted) {
      final p = await _recorder.stop();
      if (p != null) {
        try {
          File(p).deleteSync();
        } catch (_) {}
      }
      return;
    }

    _recordSeconds = 0;
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });
    if (mounted) {
      setState(() {
        _holdingLevel = level;
        _isRecording = true;
        _cancelled = false;
      });
    }
  }

  Future<void> _stopAndSend() async {
    _pressing = false;
    if (!_isRecording) return;
    _recordTimer?.cancel();
    _recordTimer = null;

    final path = await _recorder.stop();
    final cancelled = _cancelled;
    if (mounted) {
      setState(() {
        _isRecording = false;
        _holdingLevel = null;
      });
    }
    if (path == null) return;

    final file = File(path);
    if (cancelled || !await file.exists() || await file.length() < 100) {
      try {
        file.deleteSync();
      } catch (_) {}
      return;
    }

    if (mounted) setState(() => _isSending = true);
    bool success = false;
    try {
      success = await TaskViewService().pushAudio(
        task.taskId,
        file,
        widget.selectedDate,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isSending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Аудио отправлено ✓' : 'Произошла ошибка'),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  Future<void> _onTap(int level, bool enabled) async {
    if (!checkStatusPermission(context, level)) return;
    if (!enabled || task.status == level) return;
    await context.read<AdminTasksProvider>().updateTaskStatus(
      task.taskId,
      level,
      widget.selectedDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = task.hasAnyVideo;
    // Barcha videolar yuklanmaguncha tasdiqlab (sariq) bo'lmaydi
    final complete = task.videosComplete;
    final gap = widget.isTablet ? 14.0 : 8.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isRecording) ...[
          Icon(Icons.fiber_manual_record, size: 12, color: Colors.red),
          const SizedBox(width: 4),
          Text(
            _cancelled
                ? 'Отмена'
                : '${_recordSeconds ~/ 60}:${(_recordSeconds % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
          SizedBox(width: gap),
        ] else if (_isSending) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: gap),
        ],
        _circle(3, Colors.green, enabled: false),
        SizedBox(width: gap),
        _circle(2, Colors.orange, enabled: complete),
        SizedBox(width: gap),
        _circle(1, Colors.red, enabled: hasVideo),
      ],
    );
  }

  Widget _circle(int level, Color color, {required bool enabled}) {
    final current = task.status;
    final isActive = current == level;
    final isHolding = _holdingLevel == level;
    final isWaiting = task.videosComplete && current == null;
    final baseSize = widget.isTablet ? 38.0 : 28.0;
    final size = isHolding ? baseSize + 8 : baseSize;
    final letter = statusLetter(level);

    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive || isHolding ? color : color.withValues(alpha: 0.08),
        border: Border.all(
          color: isActive || isHolding
              ? color
              : color.withValues(alpha: enabled ? 0.45 : 0.25),
          width: 2,
        ),
        boxShadow: isActive || isHolding
            ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 6)]
            : const [],
      ),
      alignment: Alignment.center,
      child: isHolding
          ? Icon(Icons.mic_rounded, size: size * 0.55, color: Colors.white)
          : letter != null
          ? Text(
              letter,
              style: TextStyle(
                fontSize: size * 0.45,
                fontWeight: FontWeight.w800,
                height: 1,
                color: isActive
                    ? Colors.white
                    : color.withValues(alpha: enabled ? 0.9 : 0.45),
              ),
            )
          : isActive
          ? Icon(Icons.check, size: size * 0.55, color: Colors.white)
          : isWaiting
          ? Icon(
              Icons.check,
              size: size * 0.55,
              color: color.withValues(alpha: 0.5),
            )
          : null,
    );

    // Yashil — qo'lda bosilmaydi
    if (letter == null) return circle;

    // Uzoq bosish kartani sudrashdan (500ms) oldinroq ishga tushadi —
    // shuning uchun bosib turish ovoz yozadi, karta sudralmaydi.
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(),
              (r) => r.onTap = () => _onTap(level, enabled),
            ),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                duration: const Duration(milliseconds: 250),
              ),
              (r) => r
                ..onLongPressStart = ((_) => _startRecording(level))
                ..onLongPressMoveUpdate = (d) {
                  // Uzoqqa surib qo'yib yuborilsa — bekor qilinadi
                  final cancel = d.localOffsetFromOrigin.distance > 80;
                  if (cancel != _cancelled && _isRecording) {
                    setState(() => _cancelled = cancel);
                  }
                }
                ..onLongPressEnd = ((_) => _stopAndSend())
                ..onLongPressCancel = () => _stopAndSend(),
            ),
      },
      child: circle,
    );
  }
}

/// Ikki marta bosishni xom pointer hodisalaridan aniqlaydi — gesture
/// arenasida qatnashmaydi, shuning uchun ichidagi tugmalar va videolar
/// bir bosishda kechikmasdan ishlayveradi.
class _DoubleTapArea extends StatefulWidget {
  final VoidCallback? onDoubleTap;
  final Widget child;

  const _DoubleTapArea({required this.onDoubleTap, required this.child});

  @override
  State<_DoubleTapArea> createState() => _DoubleTapAreaState();
}

class _DoubleTapAreaState extends State<_DoubleTapArea> {
  static const _maxGap = Duration(milliseconds: 300);
  static const _maxPress = Duration(milliseconds: 250);

  Offset? _downAt;
  DateTime? _downTime;
  DateTime? _lastTapTime;
  Offset? _lastTapAt;

  @override
  Widget build(BuildContext context) {
    if (widget.onDoubleTap == null) return widget.child;
    return Listener(
      onPointerDown: (e) {
        _downAt = e.position;
        _downTime = DateTime.now();
      },
      onPointerUp: (e) {
        final downAt = _downAt;
        final downTime = _downTime;
        if (downAt == null || downTime == null) return;
        final now = DateTime.now();
        // Faqat qisqa va joyida bosish hisoblanadi (sudrash/scroll emas)
        if (now.difference(downTime) > _maxPress ||
            (e.position - downAt).distance > kTouchSlop) {
          _lastTapTime = null;
          return;
        }
        final last = _lastTapTime;
        final lastAt = _lastTapAt;
        if (last != null &&
            lastAt != null &&
            now.difference(last) <= _maxGap &&
            (e.position - lastAt).distance <= kDoubleTapSlop) {
          _lastTapTime = null;
          widget.onDoubleTap!();
        } else {
          _lastTapTime = now;
          _lastTapAt = e.position;
        }
      },
      onPointerCancel: (_) => _lastTapTime = null,
      child: widget.child,
    );
  }
}
