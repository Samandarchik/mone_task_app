import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mone_task_app/admin/service/get_excel_ui.dart';
import 'package:mone_task_app/admin/ui/video_cache_manager_page.dart';
import 'package:mone_task_app/checker/ui/player2.dart';
import 'package:mone_task_app/worker/ui/worker_audio_player.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/utils/get_color.dart';
import 'package:mone_task_app/worker/model/task_worker_model.dart';
import 'package:mone_task_app/worker/model/response_task_model.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:mone_task_app/worker/service/log_out.dart';
import 'package:mone_task_app/worker/service/task_worker_service.dart';
import 'dart:async';

import 'package:mone_task_app/worker/ui/telegram_style_video_recorder.dart';

class TaskWorkerUi extends StatefulWidget {
  const TaskWorkerUi({super.key});

  @override
  State<TaskWorkerUi> createState() => _TaskWorkerUiState();
}

class _TaskWorkerUiState extends State<TaskWorkerUi> {
  bool _isRecording = false;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  List<TaskWorkerModel> _tasks = [];
  DateTime _selectedDate = DateTime.now();

  TokenStorage tokenStorage = sl<TokenStorage>();
  UserModel? user;

  @override
  void initState() {
    super.initState();
    user = tokenStorage.getUserData();
    _fetchTasks(showLoading: true);
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

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  void _goToPrevDay() {
    setState(
      () => _selectedDate = _selectedDate.subtract(const Duration(days: 1)),
    );
    _fetchTasks(showLoading: true);
  }

  void _goToNextDay() {
    if (_isToday) return;
    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
    _fetchTasks(showLoading: true);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      locale: const Locale('ru'),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _fetchTasks(showLoading: true);
    }
  }

  Future<void> _showVideoRecorder(TaskWorkerModel task) async {
    setState(() => _isRecording = true);
    final result = await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.8),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) =>
          TelegramStyleVideoRecorder(taskId: task.id),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
              ),
              child: child,
            ),
          ),
    );
    setState(() => _isRecording = false);
    if (!context.mounted) return;
    if (result is List<XFile>) {
      await _uploadVideoSegments(task, result);
    } else if (result is XFile) {
      await _uploadVideo(task, result);
    }
  }

  Future<void> _uploadVideoSegments(
    TaskWorkerModel task,
    List<XFile> segments,
  ) async {
    try {
      final success = await TaskWorkerService().completeTaskWithSegments(
        taskId: task.id,
        segments: segments,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? "✅ Отправка успешно завершена!"
                  : "❌ Yuborishda xatolik!",
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      Future.delayed(const Duration(seconds: 2), _refresh);
    } catch (e) {
      Future.delayed(const Duration(seconds: 2), _refresh);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Xatolik: $e"), backgroundColor: Colors.red),
        );
    }
  }

  Future<void> _uploadVideo(TaskWorkerModel task, XFile video) async {
    try {
      final success = await TaskWorkerService().completeTask(
        RequestTaskModel(id: task.id, file: video),
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? "✅ Muvaffaqiyatli yuborildi!" : "❌ Yuborishda xatolik!",
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      Future.delayed(const Duration(seconds: 2), _refresh);
    } catch (e) {
      Future.delayed(const Duration(seconds: 2), _refresh);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Xatolik: $e"), backgroundColor: Colors.red),
        );
    }
  }

  Widget _buildDateSelector() {
    final dateStr = _isToday
        ? 'Bugun'
        : DateFormat('d MMMM, yyyy', 'ru').format(_selectedDate);

    return Container(
      height: 48,
      color:
          Theme.of(context).appBarTheme.backgroundColor ??
          Theme.of(context).colorScheme.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _goToPrevDay,
            icon: const Icon(Icons.chevron_left),
            iconSize: 28,
          ),
          GestureDetector(
            onTap: _pickDate,
            child: Row(
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.calendar_today_outlined, size: 16),
              ],
            ),
          ),
          IconButton(
            onPressed: _isToday ? null : _goToNextDay,
            icon: Icon(
              Icons.chevron_right,
              color: _isToday ? Colors.grey.shade400 : null,
            ),
            iconSize: 28,
          ),
        ],
      ),
    );
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
        title: Text(user?.username ?? ""),
        actions: [
          IconButton(onPressed: _handleLogout, icon: const Icon(Icons.logout)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _buildDateSelector(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading)
      return const Center(child: CircularProgressIndicator.adaptive());
    if (_hasError) return Center(child: Text("Xatolik: $_errorMessage"));

    return RefreshIndicator(
      onRefresh: () => _fetchTasks(showLoading: false),
      child: _tasks.isEmpty
          ? const Center(child: Text("Vazifalar yo'q"))
          : ListView.builder(
              itemCount: _tasks.length,
              itemBuilder: (_, i) {
                final task = _tasks[i];
                final hasAudio =
                    task.checkerAudioUrl != null &&
                    task.checkerAudioUrl!.isNotEmpty;

                return InkWell(
                  onTap: task.videoUrl == null
                      ? null
                      : () => showDialog(
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
                        ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    margin: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: getStatusColor(task.taskStatus),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${i + 1}. ${task.description}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (task.submittedBy != null)
                                    Text(
                                      "${task.submittedBy} | "
                                      "${task.submittedAt?.toLocal().hour.toString().padLeft(2, '0')}:"
                                      "${task.submittedAt?.minute.toString().padLeft(2, '0')}",
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _isRecording
                                  ? null
                                  : () => _showVideoRecorder(task),
                              icon: Icon(
                                _isRecording
                                    ? Icons.fiber_manual_record
                                    : Icons.videocam,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        if (hasAudio) ...[
                          const SizedBox(height: 8),
                          WorkerAudioPlayer(audioUrl: task.checkerAudioUrl!),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _handleLogout() async {
    await LogOutService().logOut();
    tokenStorage.removeToken();
    tokenStorage.putUserData({});
    context.pushAndRemove(LoginPage());
  }
}
