import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/video_player_provider.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:mone_task_app/core/utils/share_helper.dart';
import 'package:video_player/video_player.dart';

class CircleVideoPlayer extends StatelessWidget {
  final List<TaskModel> title;
  final List<String> videoUrls;
  final int initialIndex;
  final void Function(int taskId)? onHalfWatched;
  final DateTime selectedDate;

  const CircleVideoPlayer({
    required this.title,
    super.key,
    required this.videoUrls,
    this.initialIndex = 0,
    this.onHalfWatched,
    required this.selectedDate,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final tasksProvider = context.read<AdminTasksProvider>();
        return VideoPlayerProvider(
          videoUrls: videoUrls,
          tasks: title,
          initialIndex: initialIndex,
          onHalfWatched: onHalfWatched,
          onUpdateStatus: (taskId, status) =>
              tasksProvider.updateTaskStatus(taskId, status, tasksProvider.selectedDate),
        );
      },
      child: _CircleVideoPlayerBody(selectedDate: selectedDate),
    );
  }
}

class _CircleVideoPlayerBody extends StatefulWidget {
  final DateTime selectedDate;
  const _CircleVideoPlayerBody({required this.selectedDate});

  @override
  State<_CircleVideoPlayerBody> createState() => _CircleVideoPlayerBodyState();
}

class _CircleVideoPlayerBodyState extends State<_CircleVideoPlayerBody>
    with TickerProviderStateMixin {
  late AnimationController _animationController;

  // ── Audio Recording ───────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isSending = false;
  bool _isStarting = false; // start() jarayonida qayta bosilmasin
  bool _isStopping = false; // stop() jarayonida ikki marta yuborilmasin
  _PendingVoice? _failedVoice; // yuborilmay qolgan yozuv (qayta urinish uchun)
  int _recordSeconds = 0;
  Timer? _recordTimer;
  late AnimationController _pulseCtrl;

  // ── Audio Player ──────────────────────────────────────────────────────────
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioPlaying = false;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  bool _isAudioCompleted = false;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;

  // ── Status button Listener ────────────────────────────────────────────────
  int? _pressedLevel;
  bool _statusPointerDown = false; // barmoq status tugmasida turibdi

  // Joriy yozuv qaysi vazifaga tegishli — yozish BOSHLANGANDA olinadi,
  // shunda yozish paytida video almashsa ham boshqa vazifaga ketmaydi.
  int? _recTaskId;
  String? _recTaskDate;
  int? _recLevel; // null — status o'zgarmaydi (oddiy ovozli izoh)
  String? _recordingPath; // dispose'da tozalash uchun

  late final Animation<double> _scaleAnim;

  /// Yozish/yuborish paytida video almashtirilmaydi.
  bool get _navLocked => _isRecording || _isSending || _isStarting;
  bool _pressedInside = true;

  final Map<int, GlobalKey> _statusKeys = {
    1: GlobalKey(),
    2: GlobalKey(),
    3: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    )..forward();
    // build ichida emas — har rebuild'da yangi listener qo'shilmasin.
    _scaleAnim = Tween(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() {
        _isAudioPlaying = s == PlayerState.playing;
        if (s == PlayerState.completed) {
          _isAudioCompleted = true;
          _audioPosition = Duration.zero;
        } else if (s == PlayerState.playing) {
          _isAudioCompleted = false;
        }
      });
    });
    _positionSub = _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _audioPosition = p);
    });
    _durationSub = _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _audioDuration = d);
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseCtrl.dispose();
    // Yozish davom etayotgan bo'lsa — to'xtatib, faylni o'chiramiz.
    final recPath = _recordingPath;
    if (_isRecording || _isStarting || recPath != null) {
      _recorder
          .stop()
          .then((p) {
            final path = p ?? recPath;
            if (path != null) _deleteQuietly(File(path));
          })
          .catchError((_) {})
          .whenComplete(() => _recorder.dispose());
    } else {
      _recorder.dispose();
    }
    // Yuborilmay qolgan yozuv endi qayta yuborilmaydi — tozalanadi.
    final failed = _failedVoice;
    if (failed != null && !_isSending) _deleteQuietly(failed.file);
    _audioPlayer.dispose();
    _recordTimer?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }

  // ── Responsive ────────────────────────────────────────────────────────────

  bool get _isTablet => MediaQuery.of(context).size.shortestSide >= 600;
  double get _iconSizeLarge => _isTablet ? 50.0 : 38.0;
  double get _circleButtonSize => _isTablet ? 48.0 : 40.0;
  double get _statusCircleSize => _isTablet ? 55.0 : 34.0;
  double get _statusIconSize => _isTablet ? 20.0 : 17.0;
  double get _audioPlayButtonSize => _isTablet ? 36.0 : 32.0;
  double get _audioPlayIconSize => _isTablet ? 22.0 : 18.0;
  double get _audioMicIconSize => _isTablet ? 20.0 : 18.0;
  double get _audioTimeWidth => _isTablet ? 44.0 : 38.0;
  double get _audioTimeFontSize => _isTablet ? 13.0 : 12.0;
  double get _chipFontSize => _isTablet ? 15.0 : 12.5;
  double get _chipIconSize => _isTablet ? 16.0 : 14.0;
  double get _statusGap => _isTablet ? 20.0 : 10.0;
  double get _recordingFontSize => _isTablet ? 16.0 : 14.0;
  double get _recordingSubFontSize => _isTablet ? 13.0 : 12.0;
  double get _pulseDotSize => _isTablet ? 12.0 : 10.0;
  double get _sendIconSize => _isTablet ? 20.0 : 18.0;
  double get _barButtonSize => _isTablet ? 56.0 : 44.0;
  double get _barIconSize => _isTablet ? 28.0 : 22.0;

  // ── Share / copy link ─────────────────────────────────────────────────────

  final GlobalKey _shareButtonKey = GlobalKey();

  void _shareTaskLink(
    BuildContext context,
    VideoPlayerProvider provider,
    TaskModel? task,
  ) {
    if (task == null) return;
    if (!Platform.isWindows && provider.isPlaying) provider.togglePlayPause();

    final link = 'https://taskapi.monebakeryuz.uz/task/${task.date}/${task.taskId}';
    final box =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final Rect sharePosition;
    if (box != null) {
      final pos = box.localToGlobal(Offset.zero);
      sharePosition = Rect.fromLTWH(
        pos.dx,
        pos.dy,
        box.size.width,
        box.size.height,
      );
    } else {
      final size = MediaQuery.of(context).size;
      sharePosition = Rect.fromLTWH(
        size.width - 100,
        size.height - 100,
        100,
        100,
      );
    }
    shareTaskLink(
      title: task.task,
      link: link,
      sharePositionOrigin: sharePosition,
      context: context,
    );
  }

  // ── Audio helpers ─────────────────────────────────────────────────────────

  String? _getAudioUrl(TaskModel? task) =>
      (task != null && task.checkerAudioUrls.isNotEmpty
          ? task.checkerAudioUrls.last
          : null);

  bool _hasAudio(TaskModel? task) {
    final url = _getAudioUrl(task);
    return url != null && url.isNotEmpty;
  }

  bool _canRecord(TaskModel? task) =>
      task?.videoUrl != null && task!.videoUrl!.isNotEmpty;

  String _fullAudioUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '${AppUrls.baseUrl}/$url';
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Recording actions ─────────────────────────────────────────────────────

  /// [level] — status tugmasini bosib turib yozilganda (1/2); oddiy mic
  /// tugmasi uchun null (status o'zgarmaydi).
  Future<bool> _startRecording(
    VideoPlayerProvider provider, {
    int? level,
  }) async {
    if (_isRecording || _isSending || _isStarting || _isStopping) return false;
    _isStarting = true;
    try {
      if (!await _ensureMicPermission()) return false;
      if (!mounted) return false;

      final task = provider.currentTask;
      if (task == null) return false;

      if (provider.isPlaying) provider.togglePlayPause();
      await _audioPlayer.stop();

      final dir = await getTemporaryDirectory();
      if (!mounted) return false;
      final path =
          '${dir.path}/voice_${task.taskId}_${DateTime.now().millisecondsSinceEpoch}.m4a';

      _recordingPath = path;
      try {
        await _recorder.start(
          RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
          path: path,
        );
      } catch (e) {
        debugPrint('Yozishni boshlab boʻlmadi: $e');
        _recordingPath = null;
        if (mounted) {
          setState(() {
            _pressedLevel = null;
            _pressedInside = true;
          });
          showAppSnack(
            context,
            tr('Yozishni boshlab boʻlmadi. Qayta urinib koʻring.'),
            type: SnackType.error,
          );
        }
        return false;
      }

      // Vidjet yopilgan bo'lsa — dispose yozuvni to'xtatib, faylni o'chiradi.
      if (!mounted) return false;

      _recTaskId = task.taskId;
      _recTaskDate = task.date;
      _recLevel = level;

      _recordSeconds = 0;
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
      });

      setState(() => _isRecording = true);
    } finally {
      _isStarting = false;
    }

    // Status tugmasi: yozish boshlanguncha barmoq qo'yib yuborilgan
    // (qisqa bosish) — egasiz yozuv qolmasin.
    if (level != null && !_statusPointerDown) {
      await _cancelRecording();
      if (mounted) {
        showAppSnack(context, tr('Bosib turing va gapiring'));
      }
      return false;
    }
    return true;
  }

  /// Mikrofon ruxsati. Telefonlarda avval o'zbekcha tushuntirish ko'rsatiladi.
  /// Ruxsat oynasi ochilgan bo'lsa, bosib turish imo-ishorasi uziladi —
  /// shuning uchun yozish avtomatik boshlanmaydi, foydalanuvchi qayta bosadi.
  Future<bool> _ensureMicPermission() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        if (await Permission.microphone.isGranted) return true;
        if (!mounted) return false;
        setState(() {
          _pressedLevel = null;
          _pressedInside = true;
        });
        final ok = await ensurePermission(context, Permission.microphone);
        if (ok && mounted) {
          showAppSnack(
            context,
            tr('Ruxsat berildi. Endi ovozli xabarni qayta yozing.'),
            type: SnackType.success,
          );
        }
        return false;
      } catch (_) {
        // permission_handler ishlamasa — record paketiga tayanamiz
      }
    }
    final has = await _recorder.hasPermission();
    if (!has && mounted) {
      showAppSnack(
        context,
        tr('Mikrofonga ruxsat berilmagan. Uni sozlamalardan yoqing.'),
        type: SnackType.error,
      );
    }
    return has;
  }

  Future<void> _stopAndSend(
    VideoPlayerProvider provider, {
    bool goNext = false,
  }) async {
    // Ikki marta yuborilmasin (qo'yib yuborish + tugma bir vaqtda)
    if (!_isRecording || _isStopping) return;
    _isStopping = true;

    try {
      _recordTimer?.cancel();
      _recordTimer = null;

      String? path;
      try {
        path = await _recorder.stop();
      } catch (e) {
        debugPrint('Yozishni toʻxtatib boʻlmadi: $e');
      }
      if (mounted) {
        setState(() => _isRecording = false);
      } else {
        _isRecording = false;
      }

      path ??= _recordingPath;
      _recordingPath = null;
      final taskId = _recTaskId;
      final taskDate = _recTaskDate;
      final level = _recLevel;
      _recTaskId = null;
      _recTaskDate = null;
      _recLevel = null;

      if (path == null) return;

      final file = File(path);
      if (!await file.exists() || await file.length() < 100) {
        _deleteQuietly(file);
        return;
      }

      if (taskId == null) {
        _deleteQuietly(file);
        return;
      }

      await _uploadVoice(
        provider,
        _PendingVoice(
          file: file,
          taskId: taskId,
          taskDate: taskDate,
          level: level,
        ),
      );
    } finally {
      _isStopping = false;
    }

    // goNext: false — video o'z-o'zidan o'tmaydi
    if (goNext && provider.hasNext && mounted) {
      provider.goToNext();
    }
  }

  /// Ovozli xabarni yuboradi. Muvaffaqiyatsiz bo'lsa yozuv saqlanadi va
  /// "Qayta urinish" tugmasi ko'rsatiladi; fayl faqat muvaffaqiyatdan keyin
  /// o'chiriladi.
  Future<void> _uploadVoice(
    VideoPlayerProvider provider,
    _PendingVoice voice,
  ) async {
    if (_isSending) return;
    if (mounted) {
      setState(() => _isSending = true);
    } else {
      _isSending = true;
    }

    bool success = false;
    try {
      success = await TaskViewService().pushAudio(
        voice.taskId,
        voice.file,
        widget.selectedDate,
      );

      if (success) {
        // ✅ Faqat audio muvaffaqiyatli yuborilgandan KEYIN status yangilanadi
        // (oyna yopilgan bo'lsa ham — audio allaqachon yuborilgan).
        if (voice.level != null) {
          await provider.updateTaskStatus(
            voice.taskId,
            voice.level!,
            voice.taskDate,
          );
        }
      }
    } catch (e) {
      debugPrint('Ovozli xabar yuborilmadi: $e');
      success = false;
    }

    if (success) {
      _deleteQuietly(voice.file);
      if (identical(_failedVoice, voice)) _failedVoice = null;
    } else {
      // Faqat bitta "qayta urinish" joyi bor — eski fayl yetim qolmasin.
      final old = _failedVoice;
      if (old != null && !identical(old, voice)) _deleteQuietly(old.file);
      _failedVoice = voice;
    }

    if (!mounted) {
      _isSending = false;
      // Oyna yopilgan — qayta urinib bo'lmaydi, fayl tozalanadi.
      if (!success) _deleteQuietly(voice.file);
      return;
    }
    setState(() => _isSending = false);
    showAppSnack(
      context,
      success
          ? tr('Ovozli xabar yuborildi')
          : tr(
              'Ovozli xabar yuborilmadi. Yozuv saqlandi — «Qayta urinish»ni bosing.',
            ),
      type: success ? SnackType.success : SnackType.error,
    );
  }

  Future<void> _retryFailedVoice(VideoPlayerProvider provider) async {
    final voice = _failedVoice;
    if (voice == null || _isSending || _isRecording) return;
    if (!await voice.file.exists()) {
      if (mounted) setState(() => _failedVoice = null);
      return;
    }
    await _uploadVoice(provider, voice);
  }

  void _discardFailedVoice() {
    final voice = _failedVoice;
    if (voice == null) return;
    _deleteQuietly(voice.file);
    setState(() => _failedVoice = null);
  }

  void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording || _isStopping) return;
    _isStopping = true;
    _recordTimer?.cancel();
    _recordTimer = null;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    _isStopping = false;
    path ??= _recordingPath;
    _recordingPath = null;
    _recTaskId = null;
    _recTaskDate = null;
    _recLevel = null;
    // Bekor qilingan yozuv kerak emas
    if (path != null) _deleteQuietly(File(path));
    if (mounted) {
      setState(() {
        _isRecording = false;
      });
    } else {
      _isRecording = false;
    }
  }

  Future<void> _toggleAudioPlay(TaskModel? task) async {
    final audioUrl = _getAudioUrl(task);
    if (audioUrl == null) return;

    if (_isAudioPlaying) {
      await _audioPlayer.pause();
      return;
    }

    if (_isAudioCompleted) {
      setState(() {
        _isAudioCompleted = false;
        _audioPosition = Duration.zero;
      });
    }

    try {
      await _audioPlayer.play(UrlSource(_fullAudioUrl(audioUrl)));
    } catch (e) {
      debugPrint('Audio ijro etilmadi: $e');
      if (mounted) {
        showAppSnack(
          context,
          tr('Ovozli xabarni ochib boʻlmadi. Qayta urinib koʻring.'),
          type: SnackType.error,
        );
      }
    }
  }

  // ── Status Listener callbacks ─────────────────────────────────────────────

  bool _isInsideButton(int level, Offset globalPos) {
    final box =
        _statusKeys[level]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final local = box.globalToLocal(globalPos);
    return local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx <= box.size.width &&
        local.dy <= box.size.height;
  }

  Future<void> _onStatusPointerDown(
    PointerDownEvent event,
    VideoPlayerProvider provider,
    TaskModel task,
  ) async {
    int? tappedLevel;
    for (final level in [1, 2, 3]) {
      if (_isInsideButton(level, event.position)) {
        tappedLevel = level;
        break;
      }
    }
    if (tappedLevel == null) return;

    // Status 3 qo'lda o'zgartirib bo'lmaydi — faqat 50% video ko'rish orqali
    if (tappedLevel == 3) return;
    if (_navLocked || _isStopping) return;

    _statusPointerDown = true;
    setState(() {
      _pressedLevel = tappedLevel;
      _pressedInside = true;
    });

    // Status 1 va 2 — avval audio yoziladi, status KEYIN o'zgaradi
    if (!_isRecording && !_isSending) {
      await _startRecording(provider, level: tappedLevel);
    }
  }

  void _onStatusPointerMove(PointerMoveEvent event) {
    if (_pressedLevel == null || _pressedLevel == 3) return;
    final inside = _isInsideButton(_pressedLevel!, event.position);
    if (inside != _pressedInside) {
      setState(() => _pressedInside = inside);
    }
  }

  Future<void> _onStatusPointerUp(
    PointerUpEvent event,
    VideoPlayerProvider provider,
  ) async {
    _statusPointerDown = false;
    final level = _pressedLevel;
    final inside = _pressedInside;
    setState(() {
      _pressedLevel = null;
      _pressedInside = true;
    });

    if (level == null || level == 3) return;
    if (!_isRecording) return;

    if (inside) {
      // ✅ goNext: false — audio yuborilgandan keyin video o'tmaydi
      await _stopAndSend(provider, goNext: false);
    }
    // Tashqarida qo'yildi → manual send/delete ko'rinadi
  }

  /// Tizim ishorani bekor qildi — yozuv yo'qolmasin: qo'lda yuborish /
  /// o'chirish tugmalari ko'rsatiladi.
  void _onStatusPointerCancel(PointerCancelEvent event) {
    _statusPointerDown = false;
    if (!mounted) return;
    setState(() {
      _pressedLevel = null;
      _pressedInside = true;
    });
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VideoPlayerProvider>();
    final size = MediaQuery.of(context).size;
    final bool isTablet = size.shortestSide >= 600;

    final double circleSize = isTablet
        ? size.shortestSide * 0.7
        : size.width * 0.85;
    final double arcRadius = circleSize / 2 + 20;
    final double arcStroke = 8.0;
    final double arcBoxSize = (arcRadius + arcStroke) * 2;

    final task = provider.currentTask;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Markaziy kontent ──────────────────────────────────────────
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTimeRow(provider),
                SizedBox(height: AppSpacing.xs),
                _buildVideoCircle(
                  context,
                  provider,
                  arcBoxSize,
                  arcRadius,
                  arcStroke,
                  circleSize,
                ),
                if (task != null && task.task.isNotEmpty)
                  _buildTitleCard(task, size, isTablet),
              ],
            ),
          ),

          // ── Boshqaruv paneli (audio + status) — video ustida ──────────
          if (provider.isInitialized && !provider.hasError)
            Positioned(
              right: 20,
              top: 200,
              bottom: 0,
              child: Center(child: _buildControlPanel(provider)),
            ),

          // ── Quyi boshqaruv paneli ─────────────────────────────────────
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + AppSpacing.lg,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 720),
                child: _buildBottomBar(context, provider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────

  Widget _barButton({
    Key? key,
    required String tooltip,
    required VoidCallback? onTap,
    IconData? icon,
    Widget? child,
    bool highlighted = false,
  }) {
    final enabled = onTap != null;
    return Tooltip(
      key: key,
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedOpacity(
            opacity: enabled ? 1.0 : 0.3,
            duration: Duration(milliseconds: 200),
            child: Container(
              width: _barButtonSize,
              height: _barButtonSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: highlighted
                    ? AppColors.primary
                    : Colors.white.withValues(alpha: 0.12),
              ),
              child:
                  child ??
                  Icon(icon, color: Colors.white, size: _barIconSize),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, VideoPlayerProvider provider) {
    final ready = provider.isInitialized && !provider.hasError;
    final gap = SizedBox(width: _isTablet ? AppSpacing.md : AppSpacing.sm);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppShadows.raised,
      ),
      child: Row(
        children: [
          // Ovoz va tezlik
          _barButton(
            tooltip: provider.isMuted ? tr('Ovozni yoqish') : tr('Ovozni oʻchirish'),
            icon: provider.isMuted
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
            onTap: ready ? provider.toggleMute : null,
          ),
          gap,
          _barButton(
            tooltip: tr('Tezlik'),
            highlighted: provider.playbackSpeed != 1.0,
            onTap: ready ? provider.cycleSpeed : null,
            child: Text(
              provider.speedLabel,
              style: TextStyle(
                color: Colors.white,
                fontSize: _isTablet ? 15 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Spacer(),
          // Oldingi / Keyingi
          _barButton(
            tooltip: tr('Oldingi'),
            icon: Icons.skip_previous_rounded,
            onTap: provider.hasPrev && !_navLocked ? provider.goToPrev : null,
          ),
          gap,
          _barButton(
            tooltip: tr('Keyingi'),
            icon: Icons.skip_next_rounded,
            onTap: provider.hasNext && !_navLocked ? provider.goToNext : null,
          ),
          Spacer(),
          // Ulashish va yopish
          _barButton(
            key: _shareButtonKey,
            tooltip: Platform.isWindows
                ? tr('Havolani nusxalash')
                : tr('Ulashish'),
            icon: Platform.isWindows ? Icons.copy_rounded : Icons.share_rounded,
            onTap: () =>
                _shareTaskLink(context, provider, provider.currentTask),
          ),
          gap,
          _barButton(
            tooltip: tr('Yopish'),
            icon: Icons.close_rounded,
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ── Title card ────────────────────────────────────────────────────────────

  Widget _buildTitleCard(TaskModel task, Size size, bool isTablet) {
    return Container(
      constraints: BoxConstraints(maxWidth: 560),
      margin: EdgeInsets.symmetric(
        horizontal: size.width * 0.1,
        vertical: AppSpacing.md,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            trData(task.task),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: isTablet ? 18 : 15,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: AppSpacing.sm),
          StatusBadge.forTask(task.status ?? 1),
        ],
      ),
    );
  }

  // ── Time row ──────────────────────────────────────────────────────────────

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: _chipIconSize, color: AppColors.textSecondary),
          SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: _chipFontSize,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRow(VideoPlayerProvider provider) {
    if (_isRecording || _isSending) return SizedBox.shrink();

    final task = provider.currentTask;
    final sent = task?.submittedAt?.toLocal();
    final time = sent == null
        ? '--:--'
        : '${sent.hour.toString().padLeft(2, '0')}:'
              '${sent.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          _infoChip(Icons.schedule_rounded, time),
          if ((task?.date ?? '').isNotEmpty)
            _infoChip(Icons.calendar_today_rounded, task!.date!),
          _infoChip(
            Icons.timer_outlined,
            provider.formatDuration(provider.duration),
          ),
          if (provider.videoUrls.length > 1)
            _infoChip(
              Icons.video_library_outlined,
              '${provider.currentIndex + 1} / ${provider.videoUrls.length}',
            ),
        ],
      ),
    );
  }

  // ── Control panel ─────────────────────────────────────────────────────────

  Widget _buildControlPanel(VideoPlayerProvider provider) {
    final task = provider.currentTask;
    if (task == null) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isTablet ? 16 : 12,
        vertical: _isTablet ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.72),
        borderRadius: AppRadius.xlAll,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_isRecording)
            _buildRecordingRow(provider)
          else if (_isSending)
            _buildSendingRow()
          else if (_failedVoice != null && _failedVoice!.taskId == task.taskId)
            _buildFailedVoiceRow(provider)
          else if (_hasAudio(task))
            _buildMiniAudioPlayer(task, provider)
          else if (_canRecord(task))
            Tooltip(
              message: tr('Ovozli xabar yozish'),
              child: GestureDetector(
                onTap: () => _startRecording(provider),
                child: Container(
                  width: _circleButtonSize,
                  height: _circleButtonSize,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.mic_rounded,
                    size: _isTablet ? 25 : 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

          if (!_isRecording && !_isSending)
            SizedBox(height: _isTablet ? 12 : 10),

          if (!_isRecording && !_isSending)
            _buildStatusIndicator(provider, task),

          if (!_isRecording && !_isSending) ...[
            SizedBox(height: 6),
            Text(
              tr('Bosib turing va gapiring'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: _recordingSubFontSize - 1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Mini audio player ─────────────────────────────────────────────────────

  Widget _buildMiniAudioPlayer(
    TaskModel? task,
    VideoPlayerProvider provider,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: _isAudioPlaying ? tr('Pauza') : tr('Ovozli xabarni tinglash'),
          child: GestureDetector(
            onTap: () => _toggleAudioPlay(task),
            child: Container(
              width: _audioPlayButtonSize,
              height: _audioPlayButtonSize,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isAudioCompleted
                    ? Icons.replay_rounded
                    : (_isAudioPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                color: Colors.white,
                size: _audioPlayIconSize,
              ),
            ),
          ),
        ),
        SizedBox(width: _isTablet ? 8 : 6),
        SizedBox(
          width: _audioTimeWidth,
          child: Text(
            _isAudioPlaying || _audioPosition > Duration.zero
                ? _fmt(_audioPosition)
                : _fmt(_audioDuration),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: _audioTimeFontSize,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (_canRecord(task))
          Tooltip(
            message: tr('Yangi ovozli xabar yozish'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _startRecording(provider),
              child: Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.mic_rounded,
                  size: _audioMicIconSize,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Recording row ─────────────────────────────────────────────────────────

  Widget _buildRecordingRow(VideoPlayerProvider provider) {
    final bool showManualControls = _pressedLevel == null && _isRecording;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, _) => Container(
            width: _pulseDotSize,
            height: _pulseDotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.danger.withValues(
                alpha: 0.35 + 0.65 * _pulseCtrl.value,
              ),
            ),
          ),
        ),
        SizedBox(width: 8),
        Text(
          _fmt(Duration(seconds: _recordSeconds)),
          style: TextStyle(
            fontSize: _recordingFontSize,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),

        if (showManualControls) ...[
          SizedBox(width: _isTablet ? 16 : 12),
          // Bekor qilish
          Tooltip(
            message: tr('Bekor qilish'),
            child: GestureDetector(
              onTap: _cancelRecording,
              child: Container(
                width: _circleButtonSize,
                height: _circleButtonSize,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: _isTablet ? 25 : 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          SizedBox(width: _isTablet ? 16 : 10),
          // Yuborish — goNext: false
          Tooltip(
            message: tr('Yuborish'),
            child: GestureDetector(
              onTap: () => _stopAndSend(provider, goNext: false),
              child: Container(
                width: _circleButtonSize,
                height: _circleButtonSize,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.send_rounded,
                  size: _sendIconSize,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ] else ...[
          SizedBox(width: 10),
          Text(
            _pressedInside
                ? tr('Yuborish uchun qoʻyib yuboring')
                : tr('Barmoqni qaytaring yoki qoʻyib yuboring'),
            style: TextStyle(
              fontSize: _recordingSubFontSize,
              color: _pressedInside
                  ? Colors.white.withValues(alpha: 0.85)
                  : AppColors.warning,
            ),
          ),
        ],
      ],
    );
  }

  // ── Failed upload row ─────────────────────────────────────────────────────

  Widget _buildFailedVoiceRow(VideoPlayerProvider provider) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline_rounded,
          color: AppColors.warning,
          size: 18,
        ),
        SizedBox(width: 6),
        Text(
          tr('Yuborilmadi'),
          style: TextStyle(
            fontSize: _recordingSubFontSize,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(width: 10),
        Tooltip(
          message: tr('Oʻchirish'),
          child: GestureDetector(
            onTap: _discardFailedVoice,
            child: Container(
              width: _circleButtonSize,
              height: _circleButtonSize,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                size: _isTablet ? 25 : 20,
                color: Colors.white,
              ),
            ),
          ),
        ),
        SizedBox(width: 8),
        Tooltip(
          message: tr('Qayta urinish'),
          child: GestureDetector(
            onTap: () => _retryFailedVoice(provider),
            child: Container(
              width: _circleButtonSize,
              height: _circleButtonSize,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.refresh_rounded,
                size: _sendIconSize + 2,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Sending row ───────────────────────────────────────────────────────────

  Widget _buildSendingRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _isTablet ? 18 : 14,
          height: _isTablet ? 18 : 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
        SizedBox(width: 10),
        Text(
          tr('Yuborilmoqda...'),
          style: TextStyle(
            fontSize: _recordingSubFontSize,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  // ── Status indicator ──────────────────────────────────────────────────────

  Widget _buildStatusIndicator(
    VideoPlayerProvider provider,
    TaskModel task,
  ) {
    return Listener(
      onPointerDown: (e) => _onStatusPointerDown(e, provider, task),
      onPointerMove: _onStatusPointerMove,
      onPointerUp: (e) => _onStatusPointerUp(e, provider),
      onPointerCancel: _onStatusPointerCancel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusCircle(task, 3, statusColor(3)),
          SizedBox(width: _statusGap),
          _statusCircle(task, 2, statusColor(2)),
          SizedBox(width: _statusGap),
          _statusCircle(task, 1, statusColor(1)),
        ],
      ),
    );
  }

  Widget _statusCircle(
    TaskModel task,
    int level,
    Color activeColor,
  ) {
    final bool isActive = task.status == level;
    final bool isHolding = _pressedLevel == level;

    return Semantics(
      label: taskStatusLabel(level),
      selected: isActive,
      child: Container(
        key: _statusKeys[level],
        width: isHolding ? _statusCircleSize + 6 : _statusCircleSize,
        height: isHolding ? _statusCircleSize + 6 : _statusCircleSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isHolding || isActive
              ? activeColor
              : activeColor.withValues(alpha: 0.25),
          border: Border.all(
            color: isHolding || isActive
                ? Colors.white
                : activeColor.withValues(alpha: 0.9),
            width: isHolding ? 3 : 2,
          ),
          boxShadow: isActive || isHolding
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.45),
                    blurRadius: isHolding ? 10 : 5,
                  ),
                ]
              : [],
        ),
        child: isActive
            ? Icon(Icons.check_rounded, size: _statusIconSize, color: Colors.white)
            : (level != 3
                  ? Icon(
                      Icons.mic_rounded,
                      size: _statusIconSize - 2,
                      color: Colors.white,
                    )
                  : null),
      ),
    );
  }

  // ── Video circle ──────────────────────────────────────────────────────────

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
          CustomPaint(
            size: Size(arcBoxSize, arcBoxSize),
            painter: _CircularProgressPainter(
              progress: 1.0,
              color: AppColors.border,
              strokeWidth: arcStroke,
              radius: arcRadius,
            ),
          ),
          CustomPaint(
            size: Size(arcBoxSize, arcBoxSize),
            painter: _CircularProgressPainter(
              progress: provider.progress,
              color: AppColors.primary,
              strokeWidth: arcStroke,
              radius: arcRadius,
              showDot: true,
              dotRadius: arcStroke + 10,
            ),
          ),
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
          ScaleTransition(
            scale: _scaleAnim,
            child: GestureDetector(
              onTap: provider.isInitialized ? provider.togglePlayPause : null,
              onHorizontalDragEnd: (details) {
                if (_navLocked) return;
                if (details.primaryVelocity != null) {
                  if (details.primaryVelocity! < -300) provider.goToNext();
                  if (details.primaryVelocity! > 300) provider.goToPrev();
                }
              },
              child: Container(
                width: circleSize,
                height: circleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x40111827),
                      blurRadius: 24,
                      spreadRadius: 2,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Builder(
                        builder: (context) {
                          if (!provider.isInitialized || provider.hasError) {
                            return SizedBox.shrink();
                          }
                          // Windows: media_kit
                          if (Platform.isWindows) {
                            final mkCtrl = provider.mkVideoController;
                            if (mkCtrl == null) return SizedBox.shrink();
                            return mkv.Video(
                              controller: mkCtrl,
                              fill: Colors.black,
                            );
                          }
                          // iOS/Android/macOS: video_player
                          final ctrl = provider.controller;
                          if (ctrl == null) return SizedBox.shrink();
                          final vSize = provider.videoSize;
                          return FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: vSize.width,
                              height: vSize.height,
                              child: VideoPlayer(ctrl),
                            ),
                          );
                        },
                      ),
                      if ((!provider.isInitialized || provider.isBuffering) &&
                          !provider.hasError)
                        Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: Colors.white,
                          ),
                        ),
                      if (provider.hasError)
                        _buildErrorOverlay(provider),
                      if (provider.isInitialized &&
                          !provider.isPlaying &&
                          !provider.hasError)
                        Container(
                          color: Colors.black26,
                          child: Center(
                            child: Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.play_arrow_rounded,
                                size: _iconSizeLarge,
                                color: Colors.white,
                              ),
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

  Widget _buildErrorOverlay(VideoPlayerProvider provider) {
    final errorMessage = provider.errorMessage;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off_rounded,
              color: Colors.white70,
              size: 44,
            ),
            SizedBox(height: AppSpacing.md),
            Text(
              tr('Videoni ochib boʻlmadi'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (errorMessage != null) ...[
              SizedBox(height: AppSpacing.sm),
              Text(
                errorMessage,
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: provider.isLoading ? null : provider.initializeVideo,
              icon: Icon(Icons.refresh_rounded, size: 20),
              label: Text(tr('Qayta urinish')),
              style: FilledButton.styleFrom(
                minimumSize: Size(0, 44),
                padding: EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yuborilmay qolgan ovozli xabar — qayta yuborish uchun saqlanadi.
class _PendingVoice {
  final File file;
  final int taskId;
  final String? taskDate;
  final int? level;

  _PendingVoice({
    required this.file,
    required this.taskId,
    required this.taskDate,
    required this.level,
  });
}

// ─── Circular progress painter ──────────────────────────────────────────────

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final double radius;
  final bool showDot;
  final double dotRadius;

  const _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.radius,
    this.showDot = false,
    this.dotRadius = 9,
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
        dotRadius,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(dotX, dotY),
        dotRadius - 3,
        Paint()..color = AppColors.primary,
      );
    }
  }

  @override
  bool shouldRepaint(_CircularProgressPainter old) =>
      old.progress != progress || old.color != color;
}
