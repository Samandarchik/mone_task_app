import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mone_task_app/shared/widgets/task_reminders.dart';
import 'package:mone_task_app/shared/widgets/profile_switch_button.dart';
import 'package:mone_task_app/admin/service/get_excel_ui.dart';
import 'package:mone_task_app/admin/ui/all_task_ui.dart';
import 'package:mone_task_app/admin/ui/video_cache_manager_page.dart';
import 'package:mone_task_app/checker/ui/player2.dart';
import 'package:mone_task_app/admin/ui/audio_task_row.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/active_filial.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/home/service/api_service.dart';
import 'package:mone_task_app/home/ui/filial_select_page.dart';
import 'package:mone_task_app/home/ui/role_home.dart';
import 'package:mone_task_app/shared/services/task_prefs_service.dart';
import 'package:mone_task_app/shared/widgets/task_reorder_list.dart';
import 'package:mone_task_app/shared/widgets/task_video_strip.dart';
import 'package:mone_task_app/shared/widgets/user_avatar.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/worker/model/task_worker_model.dart';
import 'package:mone_task_app/worker/model/response_task_model.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:mone_task_app/worker/service/log_out.dart';
import 'package:mone_task_app/worker/service/task_worker_service.dart';
import 'package:mone_task_app/worker/ui/my_employees_page.dart';
import 'dart:async';

import 'package:mone_task_app/core/network/ws_service.dart';
import 'package:mone_task_app/worker/ui/telegram_style_video_recorder.dart';

class TaskWorkerUi extends StatefulWidget {
  const TaskWorkerUi({super.key});

  @override
  State<TaskWorkerUi> createState() => _TaskWorkerUiState();
}

class _TaskWorkerUiState extends State<TaskWorkerUi> {
  bool _isRecording = false;
  final TaskPrefsService _prefs = TaskPrefsService();
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  List<TaskModel> _tasks = [];
  DateTime _selectedDate = DateTime.now();

  TokenStorage tokenStorage = sl<TokenStorage>();
  UserModel? user;
  StreamSubscription? _wsSub;

  /// Worker o'z vazifalarini sotrudniklariga biriktira oladi
  bool get _isOwner => user?.role == 'worker';
  bool get _isEmployee => user?.role == 'sotrudnik';

  @override
  void initState() {
    super.initState();
    user = tokenStorage.getUserData();
    _fetchTasks(showLoading: true);
    _initWs();
    _syncUser();
    // Revizor talabi bo'lsa — ilova ochilishi bilan majburiy oyna
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkMyDemands(context);
    });
  }

  /// Ilova yopiq paytda o'zgargan ruxsatlar (masalan, «Задачи») WS orqali
  /// kelmaydi — saqlangan ma'lumotni serverdagisi bilan yangilaymiz.
  Future<void> _syncUser() async {
    final data = await ApiService().me();
    if (data == null || !mounted) return;
    final before = user;
    final updated = applyUserUpdateEvent(data);
    if (updated == null || !mounted) return;
    final filialsChanged =
        (before?.filialIds ?? const <int>[]).join(',') !=
        (updated.filialIds ?? const <int>[]).join(',');
    if (before?.role != updated.role || filialsChanged) {
      context.pushAndRemove(landingForUser(updated));
    } else {
      setState(() => user = updated);
    }
  }

  void _initWs() {
    final ws = WsService();
    ws.connect();
    _wsSub = ws.onEvent.listen((event) {
      if (event['event'] == 'task_updated') {
        _fetchTasks(showLoading: false);
      } else if (event['event'] == 'task_reminder') {
        // Vazifa vaqti keldi — ilovaning o'zida bir marta eslatma
        final data = event['data'];
        if (data is Map<String, dynamic> && mounted) {
          showTaskReminder(context, data);
        }
      } else if (event['event'] == 'task_demand') {
        if (mounted) checkMyDemands(context);
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
    if (showLoading)
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    try {
      final tasks = await TaskWorkerService().fetchTasks(date: _selectedDate);
      if (mounted)
        setState(() {
          _tasks = tasks;
          _isLoading = false;
          _hasError = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
    }
  }

  void _refresh() => _fetchTasks(showLoading: false);

  Future<void> _openEmployees() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyEmployeesPage()),
    );
    if (mounted) _refresh();
  }

  Future<void> _openTaskManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const TemplateTaskAdminUi(name: 'Задачи', category: null),
      ),
    );
    // Yangi/o'zgargan vazifalar bugungi ro'yxatga tushgan bo'lishi mumkin.
    if (mounted) _refresh();
  }

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
    // Kategoriya tanlanmagan bo'lsa — hech qanday vazifa ko'rinmaydi
    // (backend ham shunday qaytaradi).
    if (user?.role == 'worker') {
      final allowed = (user?.categories ?? const <String>[]).toSet();
      tasks = allowed.isEmpty
          ? const <TaskModel>[]
          : tasks.where((t) => allowed.contains(t.category)).toList();
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

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month - 1, now.day);
    final lastDate = now;

    const monthNames = [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь',
    ];

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
          height: 300,
          color: CupertinoColors.systemBackground.resolveFrom(ctx),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Отмена'),
                    ),
                    CupertinoButton(
                      onPressed: () {
                        final m = months[monthIdx];
                        Navigator.of(
                          ctx,
                        ).pop(DateTime(m.year, m.month, days[dayIdx]));
                      },
                      child: const Text('Выбрать'),
                    ),
                  ],
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: monthIdx,
                          ),
                          itemExtent: 32,
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
                              Center(child: Text(monthNames[m.month - 1])),
                          ],
                        ),
                      ),
                      Expanded(
                        child: CupertinoPicker(
                          key: ValueKey(monthIdx),
                          scrollController: FixedExtentScrollController(
                            initialItem: dayIdx,
                          ),
                          itemExtent: 32,
                          onSelectedItemChanged: (i) => setSt(() => dayIdx = i),
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
    );

    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _fetchTasks(showLoading: true);
    }
  }

  /// [slot] — ko'p videoli taskda qaysi joyga yoziladi (0 dan). null = keyingi bo'sh joy
  Future<void> _showVideoRecorder(TaskModel task, {int? slot}) async {
    setState(() => _isRecording = true);

    final result = await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _BlurCameraOverlay(taskId: task.taskId),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );

    setState(() => _isRecording = false);
    if (!context.mounted) return;
    if (result is List<XFile>) {
      await _uploadVideoSegments(task, result, slot);
    } else if (result is XFile) {
      await _uploadVideo(task, result, slot);
    }
  }

  Future<void> _uploadVideoSegments(
    TaskModel task,
    List<XFile> segments,
    int? slot,
  ) async {
    try {
      final success = await TaskWorkerService().completeTaskWithSegments(
        taskId: task.taskId,
        segments: segments,
        slot: slot,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? "✅ Отправка успешно завершена!"
                  : "❌ Ошибка при отправке!",
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      Future.delayed(const Duration(seconds: 2), _refresh);
    } catch (e) {
      Future.delayed(const Duration(seconds: 2), _refresh);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Ошибка: $e"), backgroundColor: Colors.red),
        );
    }
  }

  Future<void> _uploadVideo(TaskModel task, XFile video, int? slot) async {
    try {
      final success = await TaskWorkerService().completeTask(
        RequestTaskModel(id: task.taskId, file: video),
        slot: slot,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? "✅ Успешно отправлено!" : "❌ Ошибка при отправке!",
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      Future.delayed(const Duration(seconds: 2), _refresh);
    } catch (e) {
      Future.delayed(const Duration(seconds: 2), _refresh);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Ошибка: $e"), backgroundColor: Colors.red),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                onTap: () {
                  context.pop;
                  context.push(VideoCacheManagerPage());
                },
                leading: const Icon(CupertinoIcons.videocam_fill),
                title: const Text("Все задачи"),
              ),
              if (_isOwner)
                ListTile(
                  onTap: () {
                    context.pop;
                    _openEmployees();
                  },
                  leading: const Icon(Icons.groups_2_rounded),
                  title: const Text("Мои сотрудники"),
                ),
              if (!_isEmployee)
                ListTile(
                  onTap: () {
                    context.pop;
                    context.push(ExcelReportPage(filialIds: user?.filialIds));
                  },
                  leading: const Icon(CupertinoIcons.doc_plaintext),
                  title: const Text("Отчеты"),
                ),
              ListTile(
                onTap: _handleLogout,
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text("Выйти", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(user: user, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user?.fullName ?? "",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (ActiveFilial.name != null)
                    Text(
                      ActiveFilial.name!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // super_admin «Задачи» ruxsatini bergan bo'lsa — o'z filiallari
          // uchun vazifa qo'shish / tahrirlash / o'chirish.
          if (user?.canManageTasks == true)
            IconButton(
              onPressed: _openTaskManager,
              icon: const Icon(Icons.edit_note_rounded),
              tooltip: 'Управление задачами',
            ),
          if (_isOwner)
            IconButton(
              onPressed: _openEmployees,
              icon: const Icon(Icons.groups_2_rounded),
              tooltip: 'Мои сотрудники',
            ),
          if (_canSwitchFilial)
            IconButton(
              onPressed: _switchFilial,
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Сменить филиал',
            ),
          GestureDetector(
            onTap: _pickDate,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  _isToday
                      ? "Сегодня"
                      : "${_selectedDate.day}/${_selectedDate.month.toString().padLeft(2, '0')}",
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
          // Super admin shu profil nomidan kirgan bo'lsa — orqaga qaytish
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: ProfileSwitchButton()),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading)
      return const Center(child: CircularProgressIndicator.adaptive());
    if (_hasError) return Center(child: Text("Ошибка: $_errorMessage"));

    final visible = _visibleTasks;
    return RefreshIndicator(
      onRefresh: () => _fetchTasks(showLoading: false),
      child: visible.isEmpty
          ? const Center(child: Text("Нет задач"))
          // Telegram'dagidek: kartani bosib turib sudrab joyini o'zgartirish
          : ReorderableListView.builder(
              buildDefaultDragHandles: false,
              proxyDecorator: liftedTaskProxy,
              onReorderStart: reorderHaptic,
              onReorder: (o, n) => _reorder(visible, o, n > o ? n - 1 : n),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
              itemCount: visible.length,
              itemBuilder: (_, i) => KeyedSubtree(
                key: ValueKey(visible[i].taskId),
                child: _buildTaskCard(
                  visible[i],
                  i + 1,
                  i,
                  nextVideoUrl: _nextVideoUrl(visible, i),
                ),
              ),
            ),
    );
  }

  Future<void> _togglePin(TaskModel task) async {
    setState(() {
      task.pinned = !task.pinned;
      _tasks = pinnedFirst(_tasks);
    });
    final ok = await _prefs.setPinned(task.templateId, task.pinned);
    // Qadash olinganda vazifa shaxsiy tartibdagi joyiga qaytadi
    if (!ok || !task.pinned) _refresh();
  }

  Future<void> _reorder(
    List<TaskModel> visible,
    int oldIndex,
    int newIndex,
  ) async {
    final list = reorderedTasks(visible, oldIndex, newIndex);
    setState(() => _tasks = mergeOrder(_tasks, list));
    final ok = await _prefs.saveOrder([for (final t in _tasks) t.templateId]);
    if (!ok) _refresh();
  }

  List<String> _taskVideos(TaskModel task) => task.videoUrls.isNotEmpty
      ? task.videoUrls
      : (task.videoUrl != null && task.videoUrl!.isNotEmpty
            ? [task.videoUrl!]
            : const []);

  void _openVideos(TaskModel task, int index) {
    final videos = [
      for (final url in _taskVideos(task))
        url.startsWith('http') ? url : "${AppUrls.baseUrl}/$url",
    ];
    if (videos.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.white12,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: videos.length > 1
            ? _WorkerVideosPager(videoUrls: videos, initialIndex: index)
            : Center(child: CircleVideoPlayer2(videoUrl: videos.first)),
      ),
    );
  }

  Future<void> _confirmRerecord(TaskModel task, int index) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text("Переснять видео ${index + 1}?"),
        content: const Text("Старое видео будет заменено новым"),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Отмена"),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Переснять"),
          ),
        ],
      ),
    );
    if (ok == true && mounted) _showVideoRecorder(task, slot: index);
  }

  /// [index] dan keyingi birinchi videoli taskning birinchi videosi
  String? _nextVideoUrl(List<TaskModel> tasks, int index) {
    for (var j = index + 1; j < tasks.length; j++) {
      final videos = _taskVideos(tasks[j]);
      if (videos.isNotEmpty) return videos.first;
    }
    return null;
  }

  Widget _buildTaskCard(
    TaskModel task,
    int number,
    int reorderIndex, {
    String? nextVideoUrl,
  }) {
    final videos = _taskVideos(task);
    final slots = task.videoCount > videos.length
        ? task.videoCount
        : videos.length;
    final multi = task.multiVideo || task.videoCount > 1;
    // Super admin belgilagan majburiy videolar soni
    final required = task.videoCount < 1 ? 1 : task.videoCount;

    return Container(
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
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sarlavhani bosib turib sudrash — pastdagi ovoz yozish va
          // videoni uzoq bosish bilan to'qnashmaydi
          ReorderableDelayedDragStartListener(
            index: reorderIndex,
            child: Row(
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
                    '$number',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.task,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                          height: 1.3,
                          color: Color(0xFF111827),
                        ),
                      ),
                      if (task.submittedBy != null || slots > 1) ...[
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (task.submittedBy != null)
                              "${task.submittedBy} · "
                                  "${task.submittedAt?.toLocal().hour.toString().padLeft(2, '0')}:"
                                  "${task.submittedAt?.toLocal().minute.toString().padLeft(2, '0')}",
                            if (slots > 1)
                              videos.length > required
                                  ? "🎥 ${videos.length} · +${videos.length - required} доп."
                                  : task.videosComplete || videos.isEmpty
                                  ? "🎥 ${videos.length}/$slots"
                                  : "🎥 ${videos.length}/$slots · загрузите все видео",
                          ].join("   "),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildReadonlyStatus(
                  taskStatus: task.status == 0 ? null : task.status,
                  // Barcha videolar yuklanmaguncha vazifa tugallanmagan
                  hasVideo: task.videosComplete,
                ),
                const SizedBox(width: 2),
                IconButton(
                  onPressed: () => _togglePin(task),
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: task.pinned ? 'Открепить' : 'Закрепить',
                  color: task.pinned
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF9CA3AF),
                  icon: Icon(
                    task.pinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TaskVideoStrip(
            videoUrls: videos,
            slotCount: task.videoCount,
            onOpenVideo: (idx) => _openVideos(task, idx),
            nextVideoUrl: nextVideoUrl,
            // Bitta videoli taskda ham ↻ — sarlavhadagi kamera olib tashlangan
            onRerecordVideo: _isRecording
                ? null
                : (idx) => _confirmRerecord(task, idx),
            onTapEmpty: _isRecording
                ? null
                : (idx) => _showVideoRecorder(task, slot: multi ? idx : null),
            // Majburiy videolardan tashqari qo'shimcha video (oxiriga qo'shiladi)
            onAddVideo: _isRecording ? null : () => _showVideoRecorder(task),
          ),
          if (videos.isEmpty) ...[
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(Icons.timer_outlined, size: 14, color: Color(0xFF6B7280)),
                SizedBox(width: 4),
                Text(
                  "Видео минимум $kMinVideoSeconds секунд",
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          AudioTaskRow(
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

  /// Faqat ko'rsatish uchun — bosilmaydi, o'zgarmaydi.
  /// taskStatus:  null → bo'sh doira,  1 → qizil,  2 → sariq,  3 → yashil
  Widget _buildReadonlyStatus({
    required int? taskStatus,
    required bool hasVideo,
  }) {
    if (taskStatus == null) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: hasVideo
              ? Border.all(color: Colors.grey.shade400, width: 2)
              : null,
        ),
        child: hasVideo
            ? const Icon(Icons.check, size: 18, color: Colors.green)
            : null,
      );
    }

    Color color;
    switch (taskStatus) {
      case 1:
        color = Colors.red;
        break;
      case 2:
        color = Colors.orange;
        break;
      case 3:
        color = Colors.green;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 4)],
      ),
      child: const Icon(Icons.check, size: 18, color: Colors.white),
    );
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
          child: Container(color: Colors.black.withOpacity(0.4)),
        ),
        TelegramStyleVideoRecorder(taskId: taskId),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ko'p videoli task — videolarni chapga/o'ngga surib ko'rish
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerVideosPager extends StatefulWidget {
  final List<String> videoUrls;
  final int initialIndex;
  const _WorkerVideosPager({required this.videoUrls, this.initialIndex = 0});

  @override
  State<_WorkerVideosPager> createState() => _WorkerVideosPagerState();
}

class _WorkerVideosPagerState extends State<_WorkerVideosPager> {
  late int _index = widget.initialIndex;
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.videoUrls.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => Center(
            child: CircleVideoPlayer2(
              key: ValueKey(widget.videoUrls[i]),
              videoUrl: widget.videoUrls[i],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 48,
          child: Center(
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  "${_index + 1}/${widget.videoUrls.length}",
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
