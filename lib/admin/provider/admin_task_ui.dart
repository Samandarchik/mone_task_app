import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/provider/admin_task_list_widget.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/circle_video_player.dart';
import 'package:mone_task_app/admin/service/get_excel_ui.dart';
import 'package:mone_task_app/admin/ui/all_task_ui.dart';
import 'package:mone_task_app/admin/ui/user_list_page.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/active_filial.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/home/ui/filial_select_page.dart';
import 'package:mone_task_app/home/ui/role_home.dart';
import 'package:mone_task_app/shared/widgets/user_avatar.dart';
import 'package:mone_task_app/core/network/ws_service.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:mone_task_app/worker/service/log_out.dart';
import 'package:provider/provider.dart';

class AdminTaskUi extends StatefulWidget {
  const AdminTaskUi({super.key});

  @override
  State<AdminTaskUi> createState() => _AdminTaskUiState();
}

class _AdminTaskUiState extends State<AdminTaskUi>
    with SingleTickerProviderStateMixin {
  final TokenStorage _tokenStorage = sl<TokenStorage>();
  UserModel? _user;
  TabController? _tabController;
  int _lastCategoryLength = 0;
  StreamSubscription? _wsSub;

  // _selectedDate ni providerdan olamiz, bu yerda saqlamaymiz
  DateTime get _selectedDate => context.read<AdminTasksProvider>().selectedDate;

  @override
  void initState() {
    super.initState();
    _user = _tokenStorage.getUserData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AdminTasksProvider>();
      provider.init();
    });

    // Ruxsat o'zgarishi (real-time) — joriy foydalanuvchiga tegishli bo'lsa
    // landing dan qayta yo'naltiramiz (provider o'zi task_updated ni eshitadi).
    _wsSub = WsService().onEvent.listen((event) {
      if (event['event'] != 'user_updated') return;
      final data = event['data'];
      if (data is! Map<String, dynamic>) return;
      final updated = applyUserUpdateEvent(data);
      if (updated != null && mounted) {
        context.pushAndRemove(landingForUser(updated));
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  void _initTabController(int length) {
    if (_tabController == null || _lastCategoryLength != length) {
      _tabController?.dispose();
      _tabController = TabController(length: length, vsync: this);
      _lastCategoryLength = length;
    }
  }

  void _showCircleVideoPlayer(
    List<String> videoPaths,
    int startIndex,
    List<TaskModel> tasks,
  ) {
    if (videoPaths.isEmpty) return;
    final isChecker = _user?.role == "checker";
    showDialog(
      context: context,
      barrierColor: Colors.white30,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: CircleVideoPlayer(
          videoUrls: videoPaths,
          initialIndex: startIndex,
          title: tasks,
          selectedDate: _selectedDate,
          // Checker: 50% video ko'rsa avtomatik status=3
          onHalfWatched: isChecker
              ? (taskId) {
                  final provider = context.read<AdminTasksProvider>();
                  provider.updateTaskStatus(taskId, 3, _selectedDate);
                }
              : null,
        ),
      ),
    );
  }

  String _buildDateLabel(DateTime selectedDate) {
    final now = DateTime.now();
    final isToday = selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;
    if (isToday) return "Сегодня";
    final day = selectedDate.day.toString().padLeft(2, '0');
    final month = selectedDate.month.toString().padLeft(2, '0');
    if (selectedDate.year != now.year || selectedDate.month == 12) {
      return "$day/$month/${selectedDate.year}";
    }
    return "$day/$month";
  }

  Future<void> _handleDateSelection() async {
    final provider = context.read<AdminTasksProvider>();
    final currentDate = provider.selectedDate;
    final firstDate = DateTime.now().subtract(const Duration(days: 30));
    final lastDate = DateTime.now();

    const monthNames = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
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
      (m) => m.year == currentDate.year && m.month == currentDate.month,
    );
    if (monthIdx < 0) monthIdx = months.length - 1;

    var days = daysFor(months[monthIdx]);
    int dayIdx = days.indexOf(currentDate.day);
    if (dayIdx < 0) dayIdx = days.length - 1;

    void applySelection() {
      final m = months[monthIdx];
      provider.setSelectedDate(DateTime(m.year, m.month, days[dayIdx]));
    }

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final selectedMonth = months[monthIdx];
          final showYearCol =
              months.first.year != months.last.year ||
              selectedMonth.month == 12;
          return Container(
            height: 260,
            color: CupertinoColors.systemBackground.resolveFrom(ctx),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: monthIdx,
                      ),
                      itemExtent: 36,
                      looping: months.length > 1,
                      onSelectedItemChanged: (i) {
                        setSt(() {
                          monthIdx = i;
                          days = daysFor(months[monthIdx]);
                          if (dayIdx >= days.length) {
                            dayIdx = days.length - 1;
                          }
                        });
                        applySelection();
                      },
                      children: [
                        for (final m in months)
                          Center(
                            child: Text(
                              monthNames[m.month - 1],
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: CupertinoPicker(
                      key: ValueKey('day-$monthIdx'),
                      scrollController: FixedExtentScrollController(
                        initialItem: dayIdx,
                      ),
                      itemExtent: 40,
                      onSelectedItemChanged: (i) {
                        setSt(() => dayIdx = i);
                        applySelection();
                      },
                      children: [
                        for (final d in days)
                          Center(
                            child: Text(
                              '$d',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (showYearCol)
                    SizedBox(
                      width: 70,
                      child: Center(
                        child: Text(
                          '${selectedMonth.year}',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _clearVideoCache() async {
    // Qaysi kungacha bo'lgan videolarni o'chirishni so'raymiz
    DateTime selectedDate = DateTime.now();
    final confirm = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => Container(
        height: 320,
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'До какого дня удалить видео?',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: selectedDate,
                  maximumDate: DateTime.now(),
                  onDateTimeChanged: (d) => selectedDate = d,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Отмена'),
                      ),
                    ),
                    Expanded(
                      child: CupertinoButton.filled(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Удалить'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;

    // Tanlangan kunning oxirigacha (shu kun ham kiradi)
    final cutoff = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      23,
      59,
      59,
    );

    try {
      final directory = await getApplicationDocumentsDirectory();
      final videosDir = Directory('${directory.path}/videos');

      int deleted = 0;
      if (await videosDir.exists()) {
        for (final entity in videosDir.listSync()) {
          if (entity is File) {
            final stat = await entity.stat();
            if (!stat.modified.isAfter(cutoff)) {
              await entity.delete();
              deleted++;
            }
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Удалено видео: $deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool get _canSwitchFilial => (_user?.filialIds?.length ?? 0) > 1;

  void _switchFilial() {
    final ids = _user?.filialIds;
    if (ids == null || ids.length <= 1) return;
    context.push(FilialSelectPage(
      role: _user?.role ?? 'checker',
      allowedIds: ids,
      isSwitch: true,
    ));
  }

  Future<void> _handleLogout() async {
    WsService().disconnect();
    await LogOutService().logOut();
    _tokenStorage.removeToken();
    _tokenStorage.putUserData({});
    await ActiveFilial.clear();
    if (mounted) context.pushAndRemove(LoginPage());
  }

  @override
  Widget build(BuildContext context) {
    final tasksProvider = context.watch<AdminTasksProvider>();

    // selectedDate ni har doim providerdan olamiz
    final selectedDate = tasksProvider.selectedDate;

    // ── Loading state ────────────────────────────────────────────────────
    if (tasksProvider.filialsState == LoadingState.loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_user?.username ?? "")),
        body: const Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    // ── Filials error ────────────────────────────────────────────────────
    if (tasksProvider.filialsState == LoadingState.error) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              _tokenStorage.removeToken();
              _tokenStorage.putUserData({});
              context.pushAndRemove(LoginPage());
            },
          ),
          title: Text(_user?.username ?? ""),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                'Ошибка при загрузке категорий:\n${tasksProvider.filialsError}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => tasksProvider.fetchFilials(),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    // ── Empty filials ────────────────────────────────────────────────────
    if (tasksProvider.filials.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_user?.username ?? "")),
        body: const Center(child: Text("Филиалы не найдены")),
      );
    }

    // Aktiv filial tanlangan bo'lsa — faqat o'sha filial tabi ko'rinadi.
    // Aks holda (super_admin = barcha filiallar) hammasi ko'rinadi.
    final allFilials = tasksProvider.filials;
    final visible = ActiveFilial.id != null
        ? allFilials.where((f) => f.filialId == ActiveFilial.id).toList()
        : allFilials;
    final categories = visible.isEmpty ? allFilials : visible;
    _initTabController(categories.length);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(user: _user, radius: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _user?.fullName ?? "",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          if (_canSwitchFilial)
            IconButton(
              onPressed: _switchFilial,
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Сменить филиал',
            ),
          _StatusFilterButton(
            status: 3,
            color: Colors.green,
            provider: tasksProvider,
          ),
          _StatusFilterButton(
            status: 2,
            color: Colors.orange,
            provider: tasksProvider,
          ),
          _StatusFilterButton(
            status: 1,
            color: Colors.red,
            provider: tasksProvider,
          ),
          _NoVideoFilterButton(provider: tasksProvider),

          if (tasksProvider.isFilterActive)
            IconButton(
              onPressed: () => tasksProvider.clearStatusFilter(),
              icon: const Icon(Icons.filter_alt_off, size: 18),
              tooltip: 'Сбросить фильтр',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),

          GestureDetector(
            onTap: _handleDateSelection,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  _buildDateLabel(selectedDate),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ),

          // ── Menyu elementlari (drawer o'rniga) ─────────────────────────
          IconButton(
            onPressed: () => context.push(
              TemplateTaskAdminUi(
                name: _user?.username ?? "",
                category: categories,
              ),
            ),
            icon: const Icon(CupertinoIcons.list_bullet),
            tooltip: 'Все задачи',
          ),
          IconButton(
            onPressed: _clearVideoCache,
            icon: const Icon(CupertinoIcons.trash),
            tooltip: 'Очистить кэш видео',
          ),
          IconButton(
            onPressed: () => context.push(ExcelReportPage(filials: categories)),
            icon: const Icon(CupertinoIcons.doc_plaintext),
            tooltip: 'Отчеты',
          ),
          IconButton(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout, color: Colors.red),
            tooltip: 'Выйти',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  padding: EdgeInsets.zero,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: categories.map((c) => Tab(text: c.name)).toList(),
                ),
              ),
              IconButton(
                onPressed: () =>
                    context.push(UsersPage(filialModel: categories)),
                icon: const Icon(Icons.groups, color: Colors.green),
                tooltip: 'Все пользователи',
              ),
            ],
          ),
        ),
      ),
      body: _buildBody(tasksProvider, categories, selectedDate),
    );
  }

  Widget _buildBody(
    AdminTasksProvider tasksProvider,
    List<FilialModel> categories,
    DateTime selectedDate,
  ) {
    if (tasksProvider.tasksState == LoadingState.loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (tasksProvider.tasksState == LoadingState.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Ошибка: ${tasksProvider.tasksError}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => tasksProvider.fetchTasks(),
              child: const Text('Qayta urinish'),
            ),
          ],
        ),
      );
    }

    if (tasksProvider.tasks.isEmpty) {
      return const Center(child: Text("Задачи не найдены"));
    }

    return TabBarView(
      controller: _tabController,
      children: categories.map((category) {
        final filteredTasks = tasksProvider.tasksForFilial(category.filialId);

        return AdminTaskListWidget(
          role: _user?.role ?? "",
          tasks: filteredTasks,
          filialId: category.filialId,
          selectedDate: selectedDate,
          onRefresh: () => tasksProvider.fetchTasks(),
          onShowVideoPlayer: _showCircleVideoPlayer,
        );
      }).toList(),
    );
  }
}

// ─── Status filter button ────────────────────────────────────────────────────

class _StatusFilterButton extends StatelessWidget {
  final int status;
  final Color color;
  final AdminTasksProvider provider;

  const _StatusFilterButton({
    required this.status,
    required this.color,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = provider.selectedStatuses.contains(status);
    final isPhone = MediaQuery.of(context).size.shortestSide < 600;
    final double size = isPhone ? 30 : 50;
    final double iconSize = isPhone ? 18 : 32;
    final double hPadding = isPhone ? 6 : 20;

    return GestureDetector(
      onTap: () => provider.toggleStatusFilter(status),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPadding),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? color : color.withValues(alpha: 0.2),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.4),
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)]
                : [],
          ),
          child: isSelected
              ? Icon(Icons.check, size: iconSize, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

// ─── No-video filter button ──────────────────────────────────────────────────

class _NoVideoFilterButton extends StatelessWidget {
  final AdminTasksProvider provider;

  const _NoVideoFilterButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    final bool isSelected = provider.filterNoVideo;
    const Color color = Colors.blueGrey;
    final isPhone = MediaQuery.of(context).size.shortestSide < 600;
    final double size = isPhone ? 30 : 50;
    final double iconSize = isPhone ? 16 : 26;
    final double hPadding = isPhone ? 6 : 20;

    return GestureDetector(
      onTap: () => provider.toggleNoVideoFilter(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPadding),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? color : color.withValues(alpha: 0.2),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.4),
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)]
                : [],
          ),
          child: Icon(
            Icons.videocam_off,
            size: iconSize,
            color: isSelected ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}
