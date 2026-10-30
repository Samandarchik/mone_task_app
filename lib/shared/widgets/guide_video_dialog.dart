import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mone_task_app/admin/provider/circle_video_player.dart';
import 'package:mone_task_app/checker/ui/player2.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart'
    show TemplateService;
import 'package:mone_task_app/shared/models/task_model.dart';
import 'package:mone_task_app/worker/ui/telegram_style_video_recorder.dart';
import 'package:mone_task_app/shared/widgets/task_video_strip.dart';
import 'package:mone_task_app/shared/widgets/upload_progress_dialog.dart';

/// Namuna video — vazifa qanday bajarilishi kerakligi. Har bir rolda o'sha
/// rolning oddiy videolari kabi ochiladi: ishchida — aylana pleyer,
/// super admin/korrektorda ([adminStyle]) — admin pleyeri (faqat ko'rish).
/// Bir marta yuklangach keshdan — darhol va internetsiz.
/// [task.guideVideoUrl] bo'lmasa — pastda kichik «hali yuklanmagan» paneli,
/// [onUpload] berilsa unda «Снять образец» tugmasi.
Future<void> showGuideVideo(
  BuildContext context, {
  required TaskModel task,
  bool adminStyle = false,
  VoidCallback? onUpload,
}) async {
  final url = task.guideVideoUrl;
  if (url == null) {
    // ⓘ tugmasining o'zi tagida chiqadi
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black12,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, _, _) =>
          _GuideEmptyPopup(anchor: anchor, onUpload: onUpload),
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(animation),
          alignment: Alignment.topRight,
          child: child,
        ),
      ),
    );
    return;
  }
  final fullUrl = fullVideoUrl(url);
  final file = await videoCacheFile(fullUrl);
  final cached = await file.exists() && await file.length() > 0;
  if (!cached) cacheVideoInBackground(fullUrl, file);
  if (!context.mounted) return;
  final path = cached ? file.path : fullUrl;
  return showDialog(
    context: context,
    barrierColor: adminStyle ? Colors.white30 : Colors.white12,
    builder: (_) => BackdropFilter(
      filter: adminStyle
          ? ImageFilter.blur(sigmaX: 20, sigmaY: 20)
          : ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: adminStyle
          ? CircleVideoPlayer(
              videoUrls: [path],
              title: [task],
              selectedDate: DateTime.now(),
              guide: true,
            )
          : Center(child: CircleVideoPlayer2(videoUrl: path)),
    ),
  );
}

/// Namuna videoni olish — har doim kameradan, oddiy vazifa videosi oladigan
/// aylana kamera bilan (telefon va Windows). macOS'da kamera plagini yo'q —
/// u yerda faqat fayl tanlanadi (ishlab chiqish uchun).
/// Fayl yo'llari (pauza bo'lsa bir nechta bo'lak), bekor qilinsa null.
Future<List<String>?> recordGuideVideo(BuildContext context, int taskId) async {
  if (Platform.isMacOS) {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    return file == null ? null : [file.path];
  }
  final result = await Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => TelegramStyleVideoRecorder(taskId: taskId),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
  if (result is List<XFile> && result.isNotEmpty) {
    return [for (final f in result) f.path];
  }
  if (result is XFile) return [result.path];
  return null;
}

/// Vazifa kartasidagi ⓘ: namuna bo'lsa ko'k (bosilsa video ochiladi),
/// bo'lmasa kulrang. [canUpload] — namuna yo'q bo'lsa yuklash taklif qilinadi.
class GuideInfoButton extends StatelessWidget {
  final TaskModel task;
  final bool canUpload;
  final VoidCallback onUploaded;

  /// Super admin/korrektor ekrani — namuna admin pleyerida ochiladi
  final bool adminStyle;

  const GuideInfoButton({
    super.key,
    required this.task,
    required this.canUpload,
    required this.onUploaded,
    this.adminStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final url = task.guideVideoUrl;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showGuideVideo(
        context,
        task: task,
        adminStyle: adminStyle,
        onUpload: url == null && canUpload
            ? () async {
                if (await uploadGuideVideoFlow(
                  context,
                  templateId: task.templateId,
                  taskId: task.taskId,
                )) {
                  onUploaded();
                }
              }
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
        child: Icon(
          Icons.info_outline_rounded,
          size: 24,
          color: url != null
              ? const Color(0xFF3B82F6)
              : const Color(0xFFB0B7C3),
        ),
      ),
    );
  }
}

/// Namuna videoni tanlab yuklash (jarayon oynasi bilan). Yuklansa true.
Future<bool> uploadGuideVideoFlow(
  BuildContext context, {
  required int templateId,
  required int taskId,
}) async {
  void snack(String message, Color color) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  final List<String>? paths;
  try {
    paths = await recordGuideVideo(context, taskId);
  } catch (_) {
    snack("Не удалось открыть камеру", Colors.red);
    return false;
  }
  if (paths == null || !context.mounted) return false;

  final videoPaths = paths;
  String? error;
  try {
    final url = await runWithUploadProgress(
      context,
      title: "Загрузка образца",
      upload: (onProgress) => TemplateService().uploadGuideVideo(
        templateId,
        videoPaths,
        onProgress: onProgress,
      ),
    );
    if (url == null) error = "Не удалось загрузить видео";
  } on DioException catch (e) {
    final data = e.response?.data;
    error = data is Map && data['error'] is String
        ? data['error']
        : "Не удалось загрузить видео";
  } catch (_) {
    error = "Не удалось загрузить видео";
  }
  if (error != null) {
    snack(error, Colors.red);
    return false;
  }
  snack("Образец загружен — теперь его видят все", Colors.green);
  return true;
}

/// Namuna hali yuklanmagan — ⓘ tugmasi tagida chiqadigan kichik oyna
/// (pastroqdagi kartada joy bo'lmasa — tepasida)
class _GuideEmptyPopup extends StatelessWidget {
  final Rect? anchor;
  final VoidCallback? onUpload;

  const _GuideEmptyPopup({required this.anchor, this.onUpload});

  static const double _width = 260;
  static const double _arrow = 8;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final a =
        anchor ??
        Rect.fromCenter(
          center: Offset(screen.width / 2, screen.height / 2),
          width: 0,
          height: 0,
        );
    final width = math.min(_width, screen.width - 24);
    final left = (a.center.dx - width + 28).clamp(
      12.0,
      screen.width - width - 12,
    );
    final below = a.bottom < screen.height * 0.7;
    // Strelka ⓘ markaziga qaraydi
    final arrowX = (a.center.dx - left - _arrow).clamp(16.0, width - 32);

    final arrow = Padding(
      padding: EdgeInsets.only(left: arrowX),
      child: CustomPaint(
        size: const Size(_arrow * 2, _arrow),
        painter: _ArrowPainter(up: below),
      ),
    );
    final card = Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.videocam_outlined,
                  color: Color(0xFF3B82F6),
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  "Образца пока нет",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              onUpload != null
                  ? "Снимите один раз, как правильно выполнить — увидят все"
                  : "Как выполнить эту задачу — ещё не снято",
              style: const TextStyle(
                fontSize: 13,
                height: 1.3,
                color: Color(0xFF6B7280),
              ),
            ),
            if (onUpload != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onUpload!();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  label: const Text("Снять образец"),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Stack(
      children: [
        Positioned(
          left: left,
          width: width,
          top: below ? a.bottom + 2 : null,
          bottom: below ? null : screen.height - a.top + 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: below ? [arrow, card] : [card, arrow],
          ),
        ),
      ],
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final bool up;

  _ArrowPainter({required this.up});

  @override
  void paint(Canvas canvas, Size size) {
    final path = up
        ? (Path()
            ..moveTo(0, size.height)
            ..lineTo(size.width / 2, 0)
            ..lineTo(size.width, size.height))
        : (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width / 2, size.height)
            ..lineTo(size.width, 0));
    canvas.drawPath(path..close(), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.up != up;
}
