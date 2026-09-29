import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioTaskRow extends StatefulWidget {
  final int taskId;
  final List<String> audioUrls;
  final DateTime selectedDate;
  final Future<bool> Function(int taskId, File file, DateTime date) onPushAudio;
  final Future<bool> Function(int taskId, DateTime date, int audioIndex)
  onDeleteAudio;

  const AudioTaskRow({
    super.key,
    required this.taskId,
    required this.audioUrls,
    required this.selectedDate,
    required this.onPushAudio,
    required this.onDeleteAudio,
  });

  /// Checker/Admin uchun convenience constructor
  factory AudioTaskRow.fromCheckerTask({
    Key? key,
    required TaskModel task,
    required DateTime selectedDate,
  }) {
    final service = TaskViewService();
    return AudioTaskRow(
      key: key,
      taskId: task.taskId,
      audioUrls: task.checkerAudioUrls,
      selectedDate: selectedDate,
      onPushAudio: (id, file, date) => service.pushAudio(id, file, date),
      onDeleteAudio: (id, date, idx) => service.deleteAudio(id, date, idx),
    );
  }

  @override
  State<AudioTaskRow> createState() => _AudioTaskRowState();
}

class _AudioTaskRowState extends State<AudioTaskRow>
    with SingleTickerProviderStateMixin {
  /// Bundan qisqa yozuvlar yuborilmaydi.
  static const _minRecordDuration = Duration(seconds: 1);

  // ── Recorder ──────────────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isSending = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  final Stopwatch _recordWatch = Stopwatch();
  String? _recordingPath; // hozir yozilayotgan fayl (dispose uchun)
  late AnimationController _pulseCtrl;

  // ── Pointer / swipe state ─────────────────────────────────────────────────
  bool _recorderReady = false;
  bool _pendingAction = false;
  bool _swipedUp = false; // tepaga surildi → preview rejimi
  double _dragStartY = 0;

  // ── Preview rejimi ────────────────────────────────────────────────────────
  // Tepaga surib qo'yib yuborilganda (yoki yuborish muvaffaqiyatsiz bo'lsa):
  // tinglash + yuborish/o'chirish
  String? _previewPath;
  bool _sendFailed = false; // true — oxirgi yuborish xato bilan tugagan
  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _isPreviewPlaying = false;
  Duration _previewDuration = Duration.zero;
  Duration _previewPosition = Duration.zero;
  bool _isPreviewCompleted = false;
  StreamSubscription? _previewStateSub;
  StreamSubscription? _previewPosSub;
  StreamSubscription? _previewDurSub;

  // ── Serverga yuborilgan audio player ─────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isCompleted = false;
  bool _isDeleting = false;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;

  List<String> get _audioUrls => widget.audioUrls;

  @override
  void initState() {
    super.initState();

    // Faqat yozish paytida aylanadi (_setRecording).
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 700),
    );

    // Serverdan audio player
    _playerStateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() {
        _isPlaying = s == PlayerState.playing;
        if (s == PlayerState.completed) {
          _isCompleted = true;
          _position = Duration.zero;
        } else if (s == PlayerState.playing) {
          _isCompleted = false;
        }
      });
    });
    _positionSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durationSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    // Preview player
    _previewStateSub = _previewPlayer.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() {
        _isPreviewPlaying = s == PlayerState.playing;
        if (s == PlayerState.completed) {
          _isPreviewCompleted = true;
          _previewPosition = Duration.zero;
        } else if (s == PlayerState.playing) {
          _isPreviewCompleted = false;
        }
      });
    });
    _previewPosSub = _previewPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _previewPosition = p);
    });
    _previewDurSub = _previewPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _previewDuration = d);
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recordWatch.stop();

    // Yozish davom etayotgan bo'lsa — toza to'xtatib, faylni o'chiramiz.
    final recordingPath = _recordingPath;
    if (_isRecording || _recorderReady || recordingPath != null) {
      _recorder
          .stop()
          .then((p) => _deleteFile(p ?? recordingPath))
          .catchError((_) {})
          .whenComplete(() => _recorder.dispose());
    } else {
      _recorder.dispose();
    }

    // Yuborilmagan preview fayli (yuborish jarayonida bo'lmasa) — o'chiriladi.
    if (!_isSending) _deleteFile(_previewPath);

    _player.dispose();
    _previewPlayer.dispose();
    _pulseCtrl.dispose();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _previewStateSub?.cancel();
    _previewPosSub?.cancel();
    _previewDurSub?.cancel();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _fullAudioUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '${AppUrls.baseUrl}/$url';
  }

  static void _deleteFile(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Mikrofon ruxsati bormi? Yo'q bo'lsa — o'zbekcha tushuntirish bilan so'raydi.
  /// Ruxsat hozir berilgan bo'lsa ham `false` qaytaradi: foydalanuvchi
  /// tugmani qayta bosib turishi kerak (dialog paytida barmoq qo'yib yuborilgan).
  Future<bool> _micReady() async {
    bool granted;
    try {
      final status = await Permission.microphone.status;
      granted = status.isGranted || status.isLimited;
    } catch (_) {
      // permission_handler bu platformani qo'llamaydi (masalan, desktop)
      try {
        return await _recorder.hasPermission();
      } catch (_) {
        return false;
      }
    }
    if (granted) return true;
    if (!mounted) return false;

    final ok = await ensurePermission(context, Permission.microphone);
    if (ok && mounted) {
      showAppSnack(
        context,
        tr('Ruxsat berildi. Endi yozish uchun tugmani bosib turing.'),
        type: SnackType.success,
      );
    }
    return false;
  }

  // ── Bosib turish (hold-to-record) ────────────────────────────────────────
  //
  // LongPressGestureRecognizer (250 ms) gesture arenasida g'olib bo'ladi —
  // shuning uchun yozish boshlangach ro'yxat aylanmaydi. 250 ms dan oldin
  // barmoq surilsa, ro'yxat odatdagidek aylanadi va yozish boshlanmaydi.
  static const _holdDelay = Duration(milliseconds: 250);

  bool _holdActive = false; // barmoq bosib turibdi (long-press qabul qilingan)
  bool _isStarting = false; // _beginRecording ishlayapti
  bool _isStopping = false; // _finishRecording ishlayapti

  late final Map<Type, GestureRecognizerFactory> _gestures = {
    _HoldRecognizer: GestureRecognizerFactoryWithHandlers<_HoldRecognizer>(
      () => _HoldRecognizer(
        allow: _canStartHold,
        duration: _holdDelay,
        debugOwner: this,
      ),
      (r) => r
        ..onLongPressStart = _onHoldStart
        ..onLongPressMoveUpdate = _onHoldMove
        ..onLongPressEnd = _onHoldEnd
        ..onLongPressCancel = _onHoldCancel,
    ),
    _HintTapRecognizer:
        GestureRecognizerFactoryWithHandlers<_HintTapRecognizer>(
          () => _HintTapRecognizer(allow: _canStartHold, debugOwner: this),
          (r) => r..onTap = _onQuickTap,
        ),
  };

  /// Yangi bosishni qabul qilish mumkinmi (faqat bo'sh holatdagi mic tugmasi).
  bool _canStartHold() =>
      mounted &&
      !_isSending &&
      !_isRecording &&
      !_isStarting &&
      !_isStopping &&
      !_holdActive &&
      !_isDeleting &&
      _previewPath == null &&
      _audioUrls.length < 2;

  /// Qisqa bosish — faqat maslahat, ruxsat so'ralmaydi.
  void _onQuickTap() {
    if (!mounted) return;
    showAppSnack(context, tr('Ovoz yozish uchun tugmani bosib turing'));
  }

  void _onHoldStart(LongPressStartDetails d) {
    if (_isRecording || _isStarting || _isSending) return;
    _holdActive = true;
    _dragStartY = d.globalPosition.dy;
    _beginRecording();
  }

  void _onHoldMove(LongPressMoveUpdateDetails d) {
    if (!_isRecording) return;
    final dy = _dragStartY - d.globalPosition.dy;
    if (dy > 80 && !_swipedUp) {
      setState(() => _swipedUp = true);
    } else if (dy <= 80 && _swipedUp) {
      setState(() => _swipedUp = false);
    }
  }

  void _onHoldEnd(LongPressEndDetails d) => _releaseHold(cancelled: false);

  /// Qabul qilinishdan oldin (aylantirish, qisqa bosish) ham chaqiriladi —
  /// u holda hech narsa qilinmaydi. Qabul qilingandan keyin tizim ishorani
  /// bekor qilsa — yozuv yo'qolmasin, preview rejimiga o'tamiz.
  void _onHoldCancel() {
    if (!_holdActive) return;
    _releaseHold(cancelled: true);
  }

  Future<void> _releaseHold({required bool cancelled}) async {
    _holdActive = false;
    if (!_isRecording) return; // _beginRecording o'zi to'xtaydi
    if (cancelled) _swipedUp = true;
    if (!_recorderReady) {
      _pendingAction = true;
      return;
    }
    if (_swipedUp) {
      await _stopForPreview();
    } else {
      await _stopAndSend();
    }
  }

  void _setRecording(bool value) {
    if (!mounted) {
      // dispose'dan keyin controller'ga tegilmaydi.
      _isRecording = value;
      return;
    }
    if (value) {
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat(reverse: true);
    } else {
      _pulseCtrl.stop();
    }
    if (mounted) {
      setState(() {
        _isRecording = value;
        if (!value) _swipedUp = false;
      });
    } else {
      _isRecording = value;
    }
  }

  Future<void> _beginRecording() async {
    if (_isStarting) return;
    _isStarting = true;
    try {
      await _beginRecordingInner();
    } finally {
      _isStarting = false;
    }
  }

  Future<void> _beginRecordingInner() async {
    _swipedUp = false;
    _pendingAction = false;
    _recorderReady = false;

    if (!await _micReady()) {
      _holdActive = false;
      return;
    }
    if (!mounted) return;

    // Ruxsat tekshirilayotganda barmoq qo'yib yuborilgan bo'lsa — boshlamaymiz.
    if (!_holdActive) {
      _showHoldHint();
      return;
    }

    _setRecording(true);

    try {
      if (!await _recorder.hasPermission()) {
        _setRecording(false);
        if (mounted) {
          showAppSnack(
            context,
            tr('Mikrofonga ruxsat berilmagan'),
            type: SnackType.error,
          );
        }
        return;
      }

      await _player.stop();
      await _previewPlayer.stop();

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${widget.taskId}_${DateTime.now().millisecondsSinceEpoch}.m4a';

      if (!mounted) return;
      _recordingPath = path;
      await _recorder.start(
        RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
        path: path,
      );
    } catch (e) {
      _recordingPath = null;
      _setRecording(false);
      if (mounted) {
        showAppSnack(
          context,
          tr("Ovoz yozishni boshlab bo'lmadi. Qayta urinib ko'ring."),
          type: SnackType.error,
        );
      }
      return;
    }

    // Yozish boshlanguncha vidjet yopilgan bo'lsa — dispose tozalaydi.
    if (!mounted) return;

    _recorderReady = true;
    _recordSeconds = 0;
    _recordWatch
      ..reset()
      ..start();
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });

    if (_pendingAction) {
      _pendingAction = false;
      if (_swipedUp) {
        await _stopForPreview();
      } else {
        await _stopAndSend();
      }
    }
  }

  void _showHoldHint() {
    if (!mounted) return;
    showAppSnack(context, tr("Juda qisqa — bosib turib gapiring"));
  }

  // ── Recording actions ─────────────────────────────────────────────────────

  /// Yozishni to'xtatadi. Yaroqli fayl yo'lini qaytaradi, juda qisqa yoki
  /// xato bo'lsa — faylni o'chirib, null qaytaradi.
  Future<String?> _finishRecording() async {
    // Sinxron qo'riqlash — ikki marta to'xtatib, ikki marta yuborilmasin.
    if (!_isRecording || _isStopping) return null;
    _isStopping = true;
    try {
      return await _finishRecordingInner();
    } finally {
      _isStopping = false;
    }
  }

  Future<String?> _finishRecordingInner() async {
    _recordTimer?.cancel();
    _recordTimer = null;
    _recordWatch.stop();
    final elapsed = _recordWatch.elapsed;

    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }
    path ??= _recordingPath;
    _recordingPath = null;
    _recorderReady = false;
    _setRecording(false);

    if (path == null) return null;

    if (elapsed < _minRecordDuration) {
      _deleteFile(path);
      _showHoldHint();
      return null;
    }

    if (!await File(path).exists()) {
      if (mounted) {
        showAppSnack(
          context,
          tr("Yozuv saqlanmadi. Qayta urinib ko'ring."),
          type: SnackType.error,
        );
      }
      return null;
    }
    return path;
  }

  /// Tepaga surilmagan → to'g'ridan-to'g'ri yuborish
  Future<void> _stopAndSend() async {
    final path = await _finishRecording();
    if (path == null) return;
    await _upload(path);
  }

  /// Tepaga surildi → to'xtatib preview rejimiga o'tish + avtomatik eshitish
  Future<void> _stopForPreview() async {
    final path = await _finishRecording();
    if (path == null) return;
    if (!mounted) {
      _deleteFile(path);
      return;
    }

    setState(() {
      _previewPath = path;
      _sendFailed = false;
      _isPreviewCompleted = false;
      _previewPosition = Duration.zero;
      _previewDuration = Duration.zero;
    });

    // Avtomatik eshitishni boshlash
    try {
      await _previewPlayer.play(DeviceFileSource(path));
    } catch (_) {}
  }

  /// Faylni serverga yuboradi. Muvaffaqiyatli bo'lsa — vaqtinchalik fayl
  /// o'chiriladi; xato bo'lsa — fayl saqlanib, "Qayta yuborish" taklif qilinadi.
  Future<void> _upload(String path) async {
    if (_isSending) return; // ikki marta yuborilmasin
    // Birinchi await'dan OLDIN belgilanadi — tez ikki marta bosish ham
    // faqat bitta yuborishga olib keladi.
    _isSending = true;
    if (mounted) setState(() {});
    await _uploadLocked(path);
  }

  /// [_isSending] allaqachon `true` bo'lganda chaqiriladi va uni qaytaradi.
  Future<void> _uploadLocked(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      _isSending = false;
      if (mounted) {
        setState(() {
          _previewPath = null;
          _sendFailed = false;
        });
        showAppSnack(
          context,
          tr("Yozuv topilmadi. Qaytadan yozing."),
          type: SnackType.error,
        );
      }
      return;
    }

    bool success = false;
    try {
      success = await widget.onPushAudio(
        widget.taskId,
        file,
        widget.selectedDate,
      );
      // WS broadcast orqali provider yangilanadi
    } catch (_) {
      success = false;
    }

    if (success) {
      _deleteFile(path);
    }

    if (!mounted) {
      // Vidjet yopilgan — xato bo'lsa ham faylni qayta yuborib bo'lmaydi.
      _isSending = false;
      if (!success) _deleteFile(path);
      return;
    }

    setState(() {
      _isSending = false;
      if (success) {
        _previewPath = null;
        _sendFailed = false;
        _isPreviewPlaying = false;
        _isPreviewCompleted = false;
        _previewPosition = Duration.zero;
        _previewDuration = Duration.zero;
      } else {
        // Yozuv saqlanadi — foydalanuvchi qayta yuborishi mumkin
        _previewPath = path;
        _sendFailed = true;
      }
    });

    showAppSnack(
      context,
      success
          ? tr('Ovozli xabar yuborildi')
          : tr(
              "Ovozli xabar yuborilmadi. Internetni tekshirib, qayta yuboring.",
            ),
      type: success ? SnackType.success : SnackType.error,
    );
  }

  /// Preview → yuborish
  Future<void> _sendPreview() async {
    final path = _previewPath;
    if (path == null || _isSending) return;
    _isSending = true; // sinxron — ikki marta bosish ikki marta yubormaydi
    setState(() {});
    try {
      await _previewPlayer.stop();
    } catch (_) {}
    await _uploadLocked(path);
  }

  /// Preview → o'chirish (qaytadan yozish mumkin)
  Future<void> _discardPreview() async {
    if (_isSending) return;
    try {
      await _previewPlayer.stop();
    } catch (_) {}
    _deleteFile(_previewPath);
    if (mounted) {
      setState(() {
        _previewPath = null;
        _sendFailed = false;
        _isPreviewPlaying = false;
        _isPreviewCompleted = false;
        _previewPosition = Duration.zero;
        _previewDuration = Duration.zero;
      });
    }
  }

  /// Preview play/pause
  Future<void> _togglePreviewPlay() async {
    if (_previewPath == null) return;
    if (_isPreviewPlaying) {
      await _previewPlayer.pause();
      return;
    }
    if (_isPreviewCompleted) {
      setState(() {
        _isPreviewCompleted = false;
        _previewPosition = Duration.zero;
      });
    }
    await _previewPlayer.play(DeviceFileSource(_previewPath!));
  }

  // ── Serverdan audio play/pause ────────────────────────────────────────────

  String? _currentPlayingUrl;

  Future<void> _togglePlay(String url) async {
    // Agar boshqa audio play qilinsa, avval to'xtatish
    if (_currentPlayingUrl != null && _currentPlayingUrl != url) {
      await _player.stop();
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _isCompleted = false;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }
    _currentPlayingUrl = url;

    if (_isPlaying) {
      await _player.pause();
      return;
    }
    if (_isCompleted) {
      setState(() {
        _isCompleted = false;
        _position = Duration.zero;
      });
    }
    try {
      if (File(url).existsSync()) {
        await _player.play(DeviceFileSource(url));
        return;
      }
      await _player.play(UrlSource(_fullAudioUrl(url)));
    } catch (_) {
      if (mounted) {
        showAppSnack(
          context,
          tr("Ovozli xabarni ijro etib bo'lmadi"),
          type: SnackType.error,
        );
      }
    }
  }

  Future<void> _seekTo(double value) async {
    await _player.seek(
      Duration(
        milliseconds: (value.clamp(0.0, 1.0) * _duration.inMilliseconds)
            .round(),
      ),
    );
  }

  Future<void> _deleteAudio(int index) async {
    if (_isDeleting) return;
    final ok = await showConfirmDialog(
      context,
      title: tr("Ovozli xabarni o'chirish"),
      message: tr('Ishonchingiz komilmi? Bu amalni qaytarib boʻlmaydi.'),
      confirmLabel: tr("Ha, o'chirish"),
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _isDeleting = true);
    await _player.stop();
    bool success;
    try {
      success = await widget.onDeleteAudio(
        widget.taskId,
        widget.selectedDate,
        index,
      );
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    setState(() {
      _isDeleting = false;
      _currentPlayingUrl = null;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    if (!success) {
      showAppSnack(
        context,
        tr("Ovozli xabarni o'chirib bo'lmadi. Qayta urinib ko'ring."),
        type: SnackType.error,
      );
    }
    // WS broadcast orqali provider yangilanadi
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool idle = !_isSending && !_isRecording && _previewPath == null;
    final Widget content;
    if (_isSending) {
      content = _buildSending();
    } else if (_isRecording) {
      content = _buildRecording();
    } else if (_previewPath != null) {
      content = _buildPreview();
    } else if (_audioUrls.length < 2) {
      // Mic tugmasi (max 2 ta audio)
      content = _buildMicButton();
    } else {
      content = SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mavjud audiolar ro'yxati (har birida delete tugmasi)
        if (idle)
          for (int i = 0; i < _audioUrls.length; i++)
            _buildAudioItem(_audioUrls[i], i),
        // Kalit bilan — mic → yozish → preview holatlarida bitta
        // RawGestureDetector saqlanadi, bosib turish ishorasi uzilmaydi.
        KeyedSubtree(
          key: const ValueKey('audio-record-area'),
          child: RawGestureDetector(gestures: _gestures, child: content),
        ),
      ],
    );
  }

  // ── 1. Mic tugmasi ────────────────────────────────────────────────────────

  Widget _buildMicButton() {
    return Container(
      constraints: BoxConstraints(minHeight: 40),
      padding: EdgeInsets.fromLTRB(6, 5, 14, 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mic_none_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              tr('Ovozli xabar: yozish uchun bosib turing'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Yozilmoqda ─────────────────────────────────────────────────────────

  Widget _buildRecording() {
    final color = _swipedUp ? AppColors.warning : AppColors.danger;
    return Container(
      constraints: BoxConstraints(minHeight: 40),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _swipedUp ? AppColors.warningSoft : AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulse dot
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.35 + 0.65 * _pulseCtrl.value),
              ),
            ),
          ),
          SizedBox(width: 8),
          Text(
            _fmt(Duration(seconds: _recordSeconds)),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(width: 10),
          Icon(
            _swipedUp ? Icons.headphones_rounded : Icons.arrow_upward_rounded,
            size: 14,
            color: _swipedUp ? AppColors.warning : AppColors.textTertiary,
          ),
          SizedBox(width: 4),
          // Hint (swipe holati)
          Flexible(
            child: AnimatedSwitcher(
              duration: Duration(milliseconds: 150),
              child: Text(
                _swipedUp
                    ? tr("Qo'yib yuboring — tinglash")
                    : tr(
                        "Qo'yib yuborsangiz yuboriladi · tepaga suring — tinglash",
                      ),
                key: ValueKey(_swipedUp),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _swipedUp ? FontWeight.w600 : FontWeight.w400,
                  color: _swipedUp
                      ? AppColors.warning
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. Preview rejimi: tinglash + yuborish/o'chirish ─────────────────────

  Widget _circleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String tooltip,
    bool filled = true,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? color : color.withValues(alpha: 0.1),
        shape: CircleBorder(),
        child: InkWell(
          customBorder: CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: filled ? Colors.white : color),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final double progress = (_previewDuration.inMilliseconds > 0)
        ? (_previewPosition.inMilliseconds / _previewDuration.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;
    final accent = _sendFailed ? AppColors.danger : AppColors.warning;

    return Container(
      padding: EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: _sendFailed ? AppColors.dangerSoft : AppColors.warningSoft,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _sendFailed
                      ? Icons.error_outline_rounded
                      : Icons.headphones_rounded,
                  size: 14,
                  color: accent,
                ),
                SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _sendFailed
                        ? tr('Yuborilmadi — qayta yuboring')
                        : tr('Yuborishdan oldin tinglang'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Play / Pause / Replay
              _circleButton(
                icon: _isPreviewCompleted
                    ? Icons.replay_rounded
                    : (_isPreviewPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                color: AppColors.warning,
                tooltip: _isPreviewPlaying ? tr('Pauza') : tr('Tinglash'),
                onTap: _togglePreviewPlay,
              ),
              SizedBox(width: 6),
              // Slider + vaqt
              SizedBox(
                width: 120,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                        activeTrackColor: AppColors.warning,
                        inactiveTrackColor: AppColors.border,
                        thumbColor: AppColors.warning,
                        overlayColor: AppColors.warning.withValues(alpha: 0.15),
                      ),
                      child: Slider(
                        value: progress,
                        min: 0,
                        max: 1,
                        onChanged: (v) async {
                          await _previewPlayer.seek(
                            Duration(
                              milliseconds:
                                  (v * _previewDuration.inMilliseconds).round(),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _fmt(_previewPosition),
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            _fmt(_previewDuration),
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 6),
              // O'chirish
              _circleButton(
                icon: Icons.delete_outline_rounded,
                color: AppColors.danger,
                tooltip: tr("O'chirish"),
                filled: false,
                onTap: _discardPreview,
              ),
              SizedBox(width: 6),
              // Yuborish / Qayta yuborish
              _circleButton(
                icon: _sendFailed ? Icons.refresh_rounded : Icons.send_rounded,
                color: AppColors.success,
                tooltip: _sendFailed ? tr('Qayta yuborish') : tr('Yuborish'),
                onTap: _sendPreview,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 4. Yuborilmoqda ───────────────────────────────────────────────────────

  Widget _buildSending() {
    return Container(
      constraints: BoxConstraints(minHeight: 40),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              tr('Ovozli xabar yuborilmoqda...'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 5. Serverdan audio player (har bir audio uchun) ──────────────────────
  Widget _buildAudioItem(String url, int index) {
    final bool isThisPlaying = _currentPlayingUrl == url;
    final double progress = isThisPlaying && _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final bool finished =
        isThisPlaying && _duration > Duration.zero && _position >= _duration;

    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play / Pause / Replay
            GestureDetector(
              onTap: () => _togglePlay(url),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  finished
                      ? Icons.replay_rounded
                      : (isThisPlaying && _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            SizedBox(width: 8),
            // Slider + vaqt
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.border,
                      thumbColor: AppColors.primary,
                      overlayColor: AppColors.primary.withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: isThisPlaying ? progress : 0.0,
                      onChanged: isThisPlaying ? _seekTo : null,
                      min: 0,
                      max: 1,
                    ),
                  ),
                  if (isThisPlaying)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _fmt(_position),
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            _fmt(_duration),
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // Delete tugmasi
            IconButton(
              tooltip: tr("O'chirish"),
              onPressed: _isDeleting ? null : () => _deleteAudio(index),
              icon: _isDeleting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: AppColors.danger,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faqat [allow] ruxsat berganda bosishni kuzatadi — boshqa holatlarda
/// (preview tugmalari, yuborish) ichki tugmalar bilan raqobatlashmaydi.
class _HoldRecognizer extends LongPressGestureRecognizer {
  _HoldRecognizer({
    required this.allow,
    required super.duration,
    super.debugOwner,
  });

  final bool Function() allow;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      allow() && super.isPointerAllowed(event);
}

class _HintTapRecognizer extends TapGestureRecognizer {
  _HintTapRecognizer({required this.allow, super.debugOwner});

  final bool Function() allow;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      allow() && super.isPointerAllowed(event);
}
