import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mone_task_app/admin/service/get_excel_ui.dart';
import 'package:mone_task_app/admin/ui/video_cache_manager_page.dart';
import 'package:mone_task_app/checker/ui/player2.dart';
import 'package:mone_task_app/admin/ui/audio_task_row.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/active_filial.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
import 'package:mone_task_app/home/ui/filial_select_page.dart';
import 'package:mone_task_app/home/ui/role_home.dart';
import 'package:mone_task_app/shared/widgets/user_avatar.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/worker/model/task_worker_model.dart';
import 'package:mone_task_app/worker/model/response_task_model.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:mone_task_app/worker/service/log_out.dart';
import 'package:mone_task_app/worker/service/task_worker_service.dart';
import 'dart:async';

import 'package:mone_task_app/core/network/ws_service.dart';
import 'package:mone_task_app/worker/ui/telegram_style_video_recorder.dart';

const List<String> _monthNames = [
  'Yanvar',
  'Fevral',
  'Mart',
  'Aprel',
  'May',
  'Iyun',
  'Iyul',
  'Avgust',
  'Sentabr',
  'Oktabr',
  'Noyabr',
  'Dekabr',
];

/// Ishchi nuqtai nazaridan vazifa holati.
enum _WorkerTaskState {
  /// Video hali yuborilmagan.
  todo,

  /// Tekshiruvchi "bajarilmagan" deb belgilagan — qayta yozish kerak.
  rejected,

  /// Video yuborilgan, tekshirilmoqda.
  review,

  /// Tasdiqlangan.
  done,
}

bool _hasVideo(TaskModel t) => t.videoUrl != null && t.videoUrl!.isNotEmpty;

_WorkerTaskState _stateOf(TaskModel t) {
  switch (t.status) {
    case 3:
      return _WorkerTaskState.done;
    case 2:
      return _WorkerTaskState.review;
    case 1:
      return _WorkerTaskState.rejected;
    default:
      return _hasVideo(t) ? _WorkerTaskState.review : _WorkerTaskState.todo;
  }
}

class TaskWorkerUi extends StatefulWidget {
  const TaskWorkerUi({super.key});

  @override
  State<TaskWorkerUi> createState() => _TaskWorkerUiState();
}

class _TaskWorkerUiState extends State<TaskWorkerUi> {
  bool _isRecording = false;
  bool _isLoading = true;
  bool _hasError = false;
  List<TaskModel> _tasks = [];
  DateTime _selectedDate = DateTime.now();

  /// Tanlangan kategoriya (xom qiymat). null — barchasi.
  String? _selectedCategory;

  /// Hozir video yuborilayotgan vazifalar: taskId → progress (0..1, null — noma'lum).
  final Map<int, double?> _uploadProgress = {};

  /// Yuborilmay qolgan videolar (fayl saqlanadi) — "Qayta yuborish" uchun.
  final Map<int, Object> _failedUploads = {};

  TokenStorage tokenStorage = sl<TokenStorage>();
  UserModel? user;
  StreamSubscription? _wsSub;

  /// Har bir so'rov raqami — eskirgan (kechikib kelgan) javoblar tashlanadi.
  int _fetchSeq = 0;

  @override
  void initState() {
    super.initState();
    user = tokenStorage.getUserData();
    _fetchTasks(showLoading: true);
    _initWs();
  }

  void _initWs() {
    final ws = WsService();
    ws.connect();
    _wsSub = ws.onEvent.listen((event) {
      if (event['event'] == 'task_updated') {
        _fetchTasks(showLoading: false);
      } else if (event['event'] == 'user_updated') {
        final data = event['data'];
        if (data is Map<String, dynamic>) {
          final updated = applyUserUpdateEvent(data);
          // Ruxsatlar o'zgardi — landing dan qayta yo'naltirib UI ni yangilaymiz
          // (yangi filial paydo bo'lsa almashtirish, olib tashlansa qayta tanlash).
          if (updated != null && mounted) {
            context.pushAndRemove(landingForUser(updated));
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchTasks({bool showLoading = false}) async {
    final req = ++_fetchSeq;
    final date = _selectedDate;
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }
    try {
      final tasks = await TaskWorkerService().fetchTasks(date: date);
      if (req != _fetchSeq || !_isSameDay(date, _selectedDate)) return;
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _isLoading = false;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint('fetchTasks xatolik: $e');
      if (req != _fetchSeq || !_isSameDay(date, _selectedDate)) return;
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Ro'yxat allaqachon bor bo'lsa — uni saqlab, faqat xabar beramiz.
          if (_tasks.isEmpty || showLoading) {
            _hasError = true;
          } else {
            showAppSnack(
              context,
              tr("Yangilab bo'lmadi. Internetni tekshiring."),
              type: SnackType.error,
            );
          }
        });
      }
    }
  }

  void _refresh() => _fetchTasks(showLoading: false);

  /// Aktiv filial tanlangan bo'lsa — faqat o'sha filial tasklari ko'rinadi.
  /// Worker uchun qo'shimcha: faqat o'ziga biriktirilgan kategoriyalardagi
  /// tasklar ko'rinadi (kategoriyalar bo'sh/null bo'lsa — cheklov yo'q).
  List<TaskModel> get _visibleTasks {
    var tasks = _tasks;

    final fid = ActiveFilial.id;
    if (fid != null) {
      tasks = tasks.where((t) => t.filialId == fid).toList();
    }

    // Kategoriya bo'yicha filtrlash — faqat worker rolida.
    final cats = user?.categories;
    if (user?.role == 'worker' && cats != null && cats.isNotEmpty) {
      final allowed = cats.toSet();
      tasks = tasks.where((t) => allowed.contains(t.category)).toList();
    }

    return tasks;
  }

  bool get _canSwitchFilial => (user?.filialIds?.length ?? 0) > 1;

  Future<void> _switchFilial() async {
    final ids = user?.filialIds;
    if (ids == null || ids.length <= 1) return;
    context.push(
      FilialSelectPage(
        role: user?.role ?? 'worker',
        allowedIds: ids,
        isSwitch: true,
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _isToday => _isSameDay(_selectedDate, DateTime.now());

  String get _dateLabel {
    final now = DateTime.now();
    if (_isSameDay(_selectedDate, now)) return tr('Bugun');
    if (_isSameDay(_selectedDate, now.subtract(Duration(days: 1)))) {
      return tr('Kecha');
    }
    return '${_selectedDate.day}-${tr(_monthNames[_selectedDate.month - 1]).toLowerCase()}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month - 1, now.day);
    final lastDate = now;

    final months = <DateTime>[];
    var mCursor = DateTime(firstDate.year, firstDate.month);
    final lastMonthStart = DateTime(lastDate.year, lastDate.month);
    while (!mCursor.isAfter(lastMonthStart)) {
      months.add(mCursor);
      mCursor = DateTime(mCursor.year, mCursor.month + 1);
    }

    List<int> daysFor(DateTime month) {
      final isFirst =
          month.year == firstDate.year && month.month == firstDate.month;
      final isLast =
          month.year == lastDate.year && month.month == lastDate.month;
      final startDay = isFirst ? firstDate.day : 1;
      final endDay = isLast
          ? lastDate.day
          : DateTime(month.year, month.month + 1, 0).day;
      return [for (int i = startDay; i <= endDay; i++) i];
    }

    int monthIdx = months.indexWhere(
      (m) => m.year == _selectedDate.year && m.month == _selectedDate.month,
    );
    if (monthIdx < 0) monthIdx = months.length - 1;

    var days = daysFor(months[monthIdx]);
    int dayIdx = days.indexOf(_selectedDate.day);
    if (dayIdx < 0) dayIdx = days.length - 1;

    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          height: 320,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(tr('Bekor qilish')),
                        ),
                        Expanded(
                          child: Text(
                            tr('Sanani tanlang'),
                            textAlign: TextAlign.center,
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final m = months[monthIdx];
                            Navigator.of(
                              ctx,
                            ).pop(DateTime(m.year, m.month, days[dayIdx]));
                          },
                          child: Text(tr('Tanlash')),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: CupertinoPicker(
                            scrollController: FixedExtentScrollController(
                              initialItem: monthIdx,
                            ),
                            itemExtent: 36,
                            onSelectedItemChanged: (i) {
                              setSt(() {
                                monthIdx = i;
                                days = daysFor(months[monthIdx]);
                                if (dayIdx >= days.length) {
                                  dayIdx = days.length - 1;
                                }
                              });
                            },
                            children: [
                              for (final m in months)
                                Center(
                                  child: Text(tr(_monthNames[m.month - 1])),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: CupertinoPicker(
                            key: ValueKey(monthIdx),
                            scrollController: FixedExtentScrollController(
                              initialItem: dayIdx,
                            ),
                            itemExtent: 36,
                            onSelectedItemChanged: (i) =>
                                setSt(() => dayIdx = i),
                            children: [
                              for (final d in days) Center(child: Text('$d')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _fetchTasks(showLoading: true);
    }
  }

  Future<void> _showVideoRecorder(TaskModel task) async {
    if (_isRecording || _uploadProgress.containsKey(task.taskId)) return;
    setState(() => _isRecording = true);

    final result = await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration(milliseconds: 300),
        reverseTransitionDuration: Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _BlurCameraOverlay(taskId: task.taskId),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );

    if (!mounted) return;
    setState(() => _isRecording = false);
    if (result is List<XFile>) {
      await _uploadVideoSegments(task, result);
    } else if (result is XFile) {
      await _uploadVideo(task, result);
    }
  }

  /// Umumiy yuklash oqimi: progress, ikki marta yuborishdan himoya,
  /// xatolikda fayl saqlanib "Qayta yuborish" imkoniyati qoladi.
  Future<void> _runUpload(
    TaskModel task,
    Object payload,
    Future<bool> Function(UploadProgress onProgress) send,
  ) async {
    final id = task.taskId;
    if (_uploadProgress.containsKey(id)) return; // allaqachon yuborilmoqda
    setState(() {
      _uploadProgress[id] = null;
      _failedUploads.remove(id);
    });

    var lastPercent = -1;
    void onProgress(int sent, int total) {
      if (!mounted || total <= 0) return;
      final percent = (sent * 100 ~/ total).clamp(0, 100);
      if (percent == lastPercent) return;
      lastPercent = percent;
      setState(() => _uploadProgress[id] = percent / 100);
    }

    bool success = false;
    try {
      success = await send(onProgress);
    } catch (e) {
      debugPrint('Video yuborish xatolik: $e');
    }

    if (!mounted) {
      if (success) _deleteFiles(payload);
      return;
    }
    setState(() {
      _uploadProgress.remove(id);
      if (!success) _failedUploads[id] = payload;
    });

    if (success) {
      _deleteFiles(payload);
      showAppSnack(context, tr('Video yuborildi. Rahmat!'),
          type: SnackType.success);
      Future.delayed(Duration(seconds: 2), _refresh);
    } else {
      showAppSnack(
        context,
        tr(
          "Video yuborilmadi. Internetni tekshirib, «Qayta yuborish» tugmasini bosing.",
        ),
        type: SnackType.error,
      );
    }
  }

  /// Vaqtinchalik video fayllarni faqat muvaffaqiyatli yuborilgandan keyin
  /// o'chiramiz.
  void _deleteFiles(Object payload) {
    final files = payload is List<XFile>
        ? payload
        : (payload is XFile ? [payload] : <XFile>[]);
    for (final f in files) {
      try {
        final file = File(f.path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _uploadVideoSegments(
    TaskModel task,
    List<XFile> segments,
  ) {
    return _runUpload(
      task,
      segments,
      (onProgress) => TaskWorkerService().completeTaskWithSegments(
        taskId: task.taskId,
        segments: segments,
        onProgress: onProgress,
      ),
    );
  }

  Future<void> _uploadVideo(TaskModel task, XFile video) {
    return _runUpload(
      task,
      video,
      (onProgress) => TaskWorkerService().completeTask(
        RequestTaskModel(id: task.taskId, file: video),
        onProgress: onProgress,
      ),
    );
  }

  Future<void> _retryUpload(TaskModel task) async {
    final payload = _failedUploads[task.taskId];
    if (payload is List<XFile>) {
      await _uploadVideoSegments(task, payload);
    } else if (payload is XFile) {
      await _uploadVideo(task, payload);
    }
  }

  void _openVideo(TaskModel task) {
    if (!_hasVideo(task)) return;
    showDialog(
      context: context,
      barrierColor: Colors.white12,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Center(
          child: CircleVideoPlayer2(
            videoUrl: "${AppUrls.baseUrl}/${task.videoUrl}",
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── UI ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filialName = ActiveFilial.name;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: Row(
          children: [
            UserAvatar(user: user, radius: 18),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (user?.fullName ?? '').isEmpty
                        ? tr('Vazifalar')
                        : displayName(user?.fullName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (filialName != null && filialName.isNotEmpty)
                    InkWell(
                      onTap: _canSwitchFilial ? _switchFilial : null,
                      borderRadius: AppRadius.smAll,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.storefront_rounded,
                            size: 13,
                            color: AppColors.textSecondary,
                          ),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              displayName(filialName),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          if (_canSwitchFilial)
                            Icon(
                              Icons.expand_more_rounded,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Center(child: ThemeToggle(compact: true)),
          SizedBox(width: 6),
          ScriptToggle(compact: true),
          PopupMenuButton<String>(
            tooltip: tr('Menyu'),
            icon: Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              switch (v) {
                case 'switch':
                  _switchFilial();
                case 'cache':
                  context.push(VideoCacheManagerPage());
                case 'reports':
                  context.push(ExcelReportPage(filialIds: user?.filialIds));
                case 'logout':
                  _confirmLogout();
              }
            },
            itemBuilder: (_) => [
              if (_canSwitchFilial)
                _menuItem(
                  'switch',
                  Icons.swap_horiz_rounded,
                  tr('Filialni almashtirish'),
                ),
              _menuItem('cache', CupertinoIcons.videocam, tr('Video kesh')),
              _menuItem(
                'reports',
                CupertinoIcons.doc_plaintext,
                tr('Hisobotlar'),
              ),
              PopupMenuDivider(),
              _menuItem(
                'logout',
                Icons.logout_rounded,
                tr('Hisobdan chiqish'),
                color: AppColors.danger,
              ),
            ],
          ),
          SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 720),
          child: _buildBody(),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? AppColors.textSecondary),
          SizedBox(width: 12),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return AppLoader();
    if (_hasError) {
      return AppErrorState(onRetry: () => _fetchTasks(showLoading: true));
    }

    final visible = _visibleTasks;

    // Kategoriyalar (serverdagi tartibda, takrorlanmasdan).
    final categories = <String>[];
    for (final t in visible) {
      if (t.category.isNotEmpty && !categories.contains(t.category)) {
        categories.add(t.category);
      }
    }
    final showTabs = categories.length > 1;
    if (_selectedCategory != null && !categories.contains(_selectedCategory)) {
      _selectedCategory = null;
    }

    final shown = (!showTabs || _selectedCategory == null)
        ? visible
        : visible.where((t) => t.category == _selectedCategory).toList();

    // Bajarilmaganlar tepada, bajarilganlar pastda (tartib saqlanadi).
    final order = {
      _WorkerTaskState.rejected: 0,
      _WorkerTaskState.todo: 1,
      _WorkerTaskState.review: 2,
      _WorkerTaskState.done: 3,
    };
    final sorted = [...shown];
    final indexOf = {for (var i = 0; i < shown.length; i++) shown[i]: i};
    sorted.sort((a, b) {
      final c = order[_stateOf(a)]!.compareTo(order[_stateOf(b)]!);
      return c != 0 ? c : indexOf[a]!.compareTo(indexOf[b]!);
    });

    return RefreshIndicator(
      onRefresh: () => _fetchTasks(showLoading: false),
      child: CustomScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildSummary(visible)),
          if (showTabs)
            SliverToBoxAdapter(child: _buildCategoryTabs(categories, visible)),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppEmptyState(
                icon: Icons.task_alt_rounded,
                title: _isToday
                    ? tr("Bugun uchun vazifa yo'q")
                    : tr("Bu kun uchun vazifa yo'q"),
                message: tr(
                  "Yangi vazifa qo'shilsa, shu yerda ko'rinadi. Yangilash uchun ekranni pastga torting.",
                ),
                actionLabel: tr('Yangilash'),
                onAction: () => _fetchTasks(showLoading: true),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 32),
              sliver: SliverList.separated(
                itemCount: sorted.length,
                separatorBuilder: (_, _) => SizedBox(height: 10),
                itemBuilder: (_, i) => _buildTaskCard(sorted[i]),
                findChildIndexCallback: (key) {
                  if (key is! ValueKey<int>) return null;
                  final idx = sorted.indexWhere((t) => t.taskId == key.value);
                  // .separated: elementlar juft indekslarda (orasida ajratgich).
                  return idx < 0 ? null : idx * 2;
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummary(List<TaskModel> tasks) {
    final total = tasks.length;
    final done = tasks.where((t) {
      final s = _stateOf(t);
      return s == _WorkerTaskState.done || s == _WorkerTaskState.review;
    }).length;
    final left = total - done;
    final progress = total == 0 ? 0.0 : done / total;
    final allDone = total > 0 && left == 0;
    final t = Theme.of(context).textTheme;

    final percent = (progress * 100).round();
    final headline = total == 0
        ? tr("Vazifalar yo'q")
        : allDone
        ? tr('Hammasi bajarildi!')
        : '$left ${tr('ta vazifa qoldi')}';
    const onHero = Colors.white;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 18, 18, 18),
        decoration: BoxDecoration(
          borderRadius: AppRadius.xlAll,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: allDone
                ? [Color(0xFF12B76A), Color(0xFF0E9384)]
                : [Color(0xFF2F6BFF), Color(0xFF6E4BFF)],
          ),
          boxShadow: [
            BoxShadow(
              color: (allDone ? AppColors.success : AppColors.primary)
                  .withValues(alpha: 0.28),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sana tanlash — oq "pill"
                  Material(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: StadiumBorder(),
                    child: InkWell(
                      customBorder: StadiumBorder(),
                      onTap: _pickDate,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 14,
                              color: onHero,
                            ),
                            SizedBox(width: 6),
                            Text(
                              _dateLabel,
                              style: TextStyle(
                                color: onHero,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Icon(
                              Icons.expand_more_rounded,
                              size: 16,
                              color: onHero,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.headlineSmall?.copyWith(
                      color: onHero,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  if (total > 0) ...[
                    SizedBox(height: 4),
                    Text(
                      '$total ${tr('ta vazifadan')} $done ${tr('tasi bajarildi')}',
                      style: t.bodyMedium?.copyWith(
                        color: onHero.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                  if (!_isToday) ...[
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        tr("Siz oldingi kunni ko'ryapsiz"),
                        style: TextStyle(
                          color: onHero,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (total > 0) ...[
              SizedBox(width: 16),
              SizedBox(
                width: 84,
                height: 84,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: v,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.white.withValues(alpha: 0.22),
                        color: onHero,
                      ),
                      Center(
                        child: allDone
                            ? Icon(
                                Icons.check_rounded,
                                color: onHero,
                                size: 36,
                              )
                            : Text(
                                '$percent%',
                                style: TextStyle(
                                  color: onHero,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTabs(List<String> categories, List<TaskModel> all) {
    Widget chip(String? value, String label, int count) {
      final selected = _selectedCategory == value;
      return Padding(
        padding: EdgeInsets.only(right: 8),
        child: AnimatedScale(
          scale: selected ? 1.08 : 1.0,
          duration: Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: ChoiceChip(
            selected: selected,
            showCheckmark: false,
            label: Text('$label  $count'),
            onSelected: (_) => setState(() => _selectedCategory = value),
          ),
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(16, 4, 8, 8),
        children: [
          chip(null, tr('Barchasi'), all.length),
          for (final c in categories)
            chip(c, displayName(c), all.where((t) => t.category == c).length),
        ],
      ),
    );
  }

  Widget _buildTaskCard(TaskModel task) {
    final state = _stateOf(task);
    final isUploading = _uploadProgress.containsKey(task.taskId);
    final progress = _uploadProgress[task.taskId];
    final hasFailed = _failedUploads.containsKey(task.taskId);
    final finished =
        state == _WorkerTaskState.done || state == _WorkerTaskState.review;
    final t = Theme.of(context).textTheme;

    final StatusBadge badge = switch (state) {
      _WorkerTaskState.todo => StatusBadge(
        label: tr('Bajarilmagan'),
        color: AppColors.textSecondary,
        background: AppColors.surfaceMuted,
      ),
      _WorkerTaskState.rejected => StatusBadge(
        label: tr('Qayta yozing'),
        color: AppColors.danger,
        background: AppColors.dangerSoft,
        icon: Icons.refresh_rounded,
      ),
      _WorkerTaskState.review => StatusBadge(
        label: tr('Tekshiruvda'),
        color: AppColors.warning,
        background: AppColors.warningSoft,
        icon: Icons.schedule_rounded,
      ),
      _WorkerTaskState.done => StatusBadge(
        label: tr('Bajarildi'),
        color: AppColors.success,
        background: AppColors.successSoft,
        icon: Icons.check_rounded,
      ),
    };

    String? submittedLine;
    if (task.submittedBy != null && task.submittedBy!.isNotEmpty) {
      final at = task.submittedAt?.toLocal();
      final time = at == null
          ? ''
          : ' · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
      submittedLine = '${displayName(task.submittedBy)}$time';
    }

    Widget action;
    if (isUploading) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: null,
            icon: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, value: progress),
            ),
            label: Text(
              progress == null
                  ? tr('Yuborilmoqda...')
                  : '${tr('Yuborilmoqda...')} ${(progress * 100).round()}%',
            ),
          ),
          if (progress != null) ...[
            SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: progress, minHeight: 4),
            ),
          ],
        ],
      );
    } else if (hasFailed) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: AppColors.danger,
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr("Video yuborilmadi. Video saqlangan — qayta yuboring."),
                  style: t.bodySmall?.copyWith(color: AppColors.danger),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _retryUpload(task),
            icon: Icon(Icons.cloud_upload_rounded),
            label: Text(tr('Qayta yuborish')),
          ),
          TextButton(
            onPressed: _isRecording ? null : () => _showVideoRecorder(task),
            child: Text(tr('Yangi video yozish')),
          ),
        ],
      );
    } else if (!finished) {
      action = FilledButton.icon(
        onPressed: _isRecording ? null : () => _showVideoRecorder(task),
        icon: Icon(Icons.videocam_rounded),
        label: Text(
          state == _WorkerTaskState.rejected
              ? tr('Qaytadan yozish')
              : tr('Video yozish'),
        ),
      );
    } else {
      action = Row(
        children: [
          if (_hasVideo(task))
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openVideo(task),
                icon: Icon(Icons.play_circle_outline_rounded),
                label: Text(tr("Videoni ko'rish")),
              ),
            ),
          if (_hasVideo(task)) SizedBox(width: 8),
          TextButton.icon(
            onPressed: _isRecording ? null : () => _showVideoRecorder(task),
            icon: Icon(Icons.refresh_rounded, size: 18),
            label: Text(tr('Qaytadan')),
          ),
        ],
      );
    }

    return Container(
      key: ValueKey(task.taskId),
      decoration: BoxDecoration(
        color: finished ? AppColors.surfaceMuted : AppColors.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: state == _WorkerTaskState.rejected
              ? AppColors.danger.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 2, right: 10),
                child: Icon(
                  finished
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: state == _WorkerTaskState.done
                      ? AppColors.success
                      : state == _WorkerTaskState.review
                      ? AppColors.warning
                      : AppColors.textTertiary,
                ),
              ),
              Expanded(
                child: Text(
                  trData(task.task),
                  style: t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: finished
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              SizedBox(width: 8),
              badge,
            ],
          ),
          if (submittedLine != null) ...[
            SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.only(left: 32),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 15,
                    color: AppColors.textTertiary,
                  ),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      submittedLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 12),
          SizedBox(width: double.infinity, child: action),
          // Doim o'rnatilgan holda qoladi: holat o'zgarganda yuborilmagan
          // ovozli xabar (preview / qayta yuborish) yo'qolmasin.
          SizedBox(height: 8),
          AudioTaskRow(
            key: ValueKey('audio_${task.taskId}'),
            taskId: task.taskId,
            audioUrls: task.checkerAudioUrls,
            selectedDate: _selectedDate,
            onPushAudio: (id, file, date) =>
                TaskWorkerService().pushAudio(id, file, date),
            onDeleteAudio: (id, date, idx) =>
                TaskWorkerService().deleteAudio(id, date, idx),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showConfirmDialog(
      context,
      title: tr('Hisobdan chiqish'),
      message: tr('Hisobdan chiqmoqchimisiz?'),
      confirmLabel: tr('Chiqish'),
      destructive: true,
    );
    if (ok) await _handleLogout();
  }

  Future<void> _handleLogout() async {
    WsService().disconnect();
    await LogOutService().logOut();
    tokenStorage.removeToken();
    tokenStorage.putUserData({});
    await ActiveFilial.clear();
    if (mounted) context.pushAndRemove(LoginPage());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Orqa sahifa (tasklar) ustiga blur + kamera overlay
// ─────────────────────────────────────────────────────────────────────────────
class _BlurCameraOverlay extends StatelessWidget {
  final int taskId;
  const _BlurCameraOverlay({required this.taskId});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(color: Colors.black.withValues(alpha: 0.4)),
        ),
        TelegramStyleVideoRecorder(taskId: taskId),
      ],
    );
  }
}
