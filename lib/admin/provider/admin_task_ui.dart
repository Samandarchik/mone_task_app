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
import 'package:mone_task_app/admin/provider/my_drawer.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/active_filial.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/home/ui/filial_select_page.dart';
import 'package:mone_task_app/home/ui/role_home.dart';
import 'package:mone_task_app/core/network/ws_service.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:mone_task_app/worker/service/log_out.dart';
import 'package:provider/provider.dart';

const _monthNames = [
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

class AdminTaskUi extends StatefulWidget {
  const AdminTaskUi({super.key});

  @override
  State<AdminTaskUi> createState() => _AdminTaskUiState();
}

class _AdminTaskUiState extends State<AdminTaskUi>
    with TickerProviderStateMixin {
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

  // Filiallar soni o'zgarsa controller qayta yaratiladi (shuning uchun
  // TickerProviderStateMixin) — joriy tab indeksi saqlanadi va chegaralanadi.
  void _initTabController(int length) {
    if (_tabController == null || _lastCategoryLength != length) {
      final previousIndex = _tabController?.index ?? _shownTabIndex;
      final initialIndex = previousIndex.clamp(0, length - 1);
      _tabController?.removeListener(_onTabChanged);
      _tabController?.dispose();
      _tabController = TabController(
        length: length,
        vsync: this,
        initialIndex: initialIndex,
      )..addListener(_onTabChanged);
      _lastCategoryLength = length;
      _shownTabIndex = initialIndex;
    }
  }

  int _shownTabIndex = 0;

  // Sarlavhadagi aktiv filial nomini yangilash uchun.
  void _onTabChanged() {
    final i = _tabController?.index ?? 0;
    if (i != _shownTabIndex && mounted) {
      setState(() => _shownTabIndex = i);
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

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _buildDateLabel(DateTime selectedDate) {
    final now = DateTime.now();
    if (_sameDay(selectedDate, now)) return tr('Bugun');
    if (_sameDay(selectedDate, now.subtract(Duration(days: 1)))) {
      return tr('Kecha');
    }
    final month = tr(_monthNames[selectedDate.month - 1]).toLowerCase();
    final label = '${selectedDate.day}-$month';
    if (selectedDate.year != now.year) return '$label ${selectedDate.year}';
    return label;
  }

  Future<void> _handleDateSelection() async {
    final provider = context.read<AdminTasksProvider>();
    final currentDate = provider.selectedDate;
    final firstDate = DateTime.now().subtract(Duration(days: 30));
    final lastDate = DateTime.now();

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

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final selectedMonth = months[monthIdx];
          final showYearCol =
              months.first.year != months.last.year ||
              selectedMonth.month == 12;
          final t = Theme.of(ctx).textTheme;
          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr('Sanani tanlang'),
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          final now = DateTime.now();
                          if (!_sameDay(provider.selectedDate, now)) {
                            provider.setSelectedDate(
                              DateTime(now.year, now.month, now.day),
                            );
                          }
                          Navigator.pop(ctx);
                        },
                        child: Text(tr('Bugun')),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 216,
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: monthIdx,
                          ),
                          itemExtent: 40,
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
                                  tr(_monthNames[m.month - 1]),
                                  style: TextStyle(fontSize: 20),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
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
                                  style: TextStyle(
                                    fontSize: 22,
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
                              style: TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(tr('Tayyor')),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _clearVideoCache() async {
    // Qaysi kungacha bo'lgan videolarni o'chirishni so'raymiz
    DateTime selectedDate = DateTime.now();
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Keshni tozalash'),
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    tr(
                      "Tanlangan kungacha (shu kun ham) yuklab olingan videolar qurilmadan o'chiriladi.",
                    ),
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 200,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: selectedDate,
                maximumDate: DateTime.now(),
                onDateTimeChanged: (d) => selectedDate = d,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(tr('Bekor qilish')),
                    ),
                  ),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(tr("O'chirish")),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
        showAppSnack(
          context,
          "${tr("O'chirilgan videolar")}: $deleted",
          type: SnackType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnack(context, '${tr('Xatolik')}: $e', type: SnackType.error);
      }
    }
  }

  // super_admin va checker barcha filiallarni ko'radi — filial filtri yo'q.
  bool get _seesAllFilials =>
      _user?.role == 'super_admin' || _user?.role == 'checker';

  bool get _canSwitchFilial =>
      !_seesAllFilials && (_user?.filialIds?.length ?? 0) > 1;

  void _switchFilial() {
    final ids = _user?.filialIds;
    if (ids == null || ids.length <= 1) return;
    context.push(
      FilialSelectPage(
        role: _user?.role ?? 'checker',
        allowedIds: ids,
        isSwitch: true,
      ),
    );
  }

  Future<void> _handleLogout() async {
    WsService().disconnect();
    await LogOutService().logOut();
    _tokenStorage.removeToken();
    _tokenStorage.putUserData({});
    await ActiveFilial.clear();
    if (mounted) context.pushAndRemove(LoginPage());
  }

  AppBar _simpleAppBar({Widget? leading}) => AppBar(
    leading: leading,
    title: Text(
      'MONE TASK',
      style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
    ),
    actions: [
      Center(child: ThemeToggle(compact: true)),
      SizedBox(width: 8),
      Padding(
        padding: EdgeInsets.only(right: 12),
        child: Center(child: ScriptToggle(compact: true)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final tasksProvider = context.watch<AdminTasksProvider>();

    // selectedDate ni har doim providerdan olamiz
    final selectedDate = tasksProvider.selectedDate;

    // ── Loading state ────────────────────────────────────────────────────
    if (tasksProvider.filialsState == LoadingState.loading) {
      return Scaffold(appBar: _simpleAppBar(), body: AppLoader());
    }

    // ── Filials error ────────────────────────────────────────────────────
    if (tasksProvider.filialsState == LoadingState.error) {
      return Scaffold(
        appBar: _simpleAppBar(
          leading: IconButton(
            icon: Icon(Icons.logout_rounded),
            tooltip: tr('Chiqish'),
            onPressed: () async {
              final ok = await showConfirmDialog(
                context,
                title: tr('Hisobdan chiqish'),
                message: tr('Hisobdan chiqishni xohlaysizmi?'),
                confirmLabel: tr('Chiqish'),
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              _tokenStorage.removeToken();
              _tokenStorage.putUserData({});
              context.pushAndRemove(LoginPage());
            },
          ),
        ),
        body: AppErrorState(
          message: tr(
            "Filiallar roʻyxatini yuklab boʻlmadi. Internet aloqasini tekshirib, qayta urinib koʻring.",
          ),
          onRetry: () => tasksProvider.fetchFilials(),
        ),
      );
    }

    // ── Empty filials ────────────────────────────────────────────────────
    if (tasksProvider.filials.isEmpty) {
      return Scaffold(
        appBar: _simpleAppBar(),
        body: AppEmptyState(
          icon: Icons.storefront_rounded,
          title: tr('Filiallar topilmadi'),
          message: tr(
            "Sizga hali filial biriktirilmagan. Administratorga murojaat qiling.",
          ),
          actionLabel: tr('Yangilash'),
          onAction: () => tasksProvider.fetchFilials(),
        ),
      );
    }

    // super_admin va checker (Tekshiruvchi) barcha filiallarni ko'radi.
    // Aks holda aktiv filial tanlangan bo'lsa — faqat o'sha filial tabi ko'rinadi.
    final allFilials = tasksProvider.filials;
    final visible = (!_seesAllFilials && ActiveFilial.id != null)
        ? allFilials.where((f) => f.filialId == ActiveFilial.id).toList()
        : allFilials;
    final categories = visible.isEmpty ? allFilials : visible;
    _initTabController(categories.length);

    final activeIndex = (_tabController?.index ?? 0).clamp(
      0,
      categories.length - 1,
    );
    final activeFilial = displayName(categories[activeIndex].name);
    final isNarrow = MediaQuery.sizeOf(context).width < 420;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      drawer: MyDrawer(
        categories: categories,
        user: _user,
        onLogout: _handleLogout,
        onClearCache: _clearVideoCache,
        onSwitchFilial: _canSwitchFilial ? _switchFilial : null,
      ),
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('Vazifalar'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 19,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storefront_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: 4),
                Flexible(
                  child: Text(
                    activeFilial,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          _DateChip(
            label: _buildDateLabel(selectedDate),
            onTap: _handleDateSelection,
          ),
          SizedBox(width: 6),
          Center(child: ThemeToggle(compact: true)),
          SizedBox(width: 6),
          isNarrow ? _ScriptMiniToggle() : ScriptToggle(compact: true),
          SizedBox(width: 12),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(kTextTabBarHeight),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.symmetric(horizontal: 4),
              tabs: [
                for (int i = 0; i < categories.length; i++)
                  _FilialTab(
                    name: displayName(categories[i].name),
                    count: tasksProvider.tasksState == LoadingState.loaded
                        ? tasksProvider
                              .tasksForFilial(categories[i].filialId)
                              .length
                        : null,
                    selected: i == activeIndex,
                  ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _FilterBar(provider: tasksProvider),
          Expanded(child: _buildBody(tasksProvider, categories, selectedDate)),
        ],
      ),
    );
  }

  Widget _buildBody(
    AdminTasksProvider tasksProvider,
    List<FilialModel> categories,
    DateTime selectedDate,
  ) {
    if (tasksProvider.tasksState == LoadingState.loading) {
      return AppLoader();
    }

    if (tasksProvider.tasksState == LoadingState.error) {
      return AppErrorState(
        message: tr(
          "Vazifalarni yuklab boʻlmadi. Internet aloqasini tekshirib, qayta urinib koʻring.",
        ),
        onRetry: () => tasksProvider.fetchTasks(),
      );
    }

    if (tasksProvider.tasks.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => tasksProvider.fetchTasks(),
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: AppEmptyState(
                icon: Icons.event_available_rounded,
                title: tr("Bu kunga vazifa yoʻq"),
                message: tr("Boshqa sanani tanlang yoki keyinroq yangilang."),
                actionLabel: tr('Sanani tanlash'),
                onAction: _handleDateSelection,
              ),
            ),
          ),
        ),
      );
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

// ─── Filial tab (nom + vazifalar soni) ───────────────────────────────────────

class _FilialTab extends StatelessWidget {
  const _FilialTab({
    required this.name,
    required this.count,
    required this.selected,
  });

  final String name;
  final int? count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 180),
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (count != null) ...[
            SizedBox(width: 6),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: selected ? 13 : 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Sana tugmasi ────────────────────────────────────────────────────────────

class _DateChip extends StatelessWidget {
  const _DateChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr('Sanani tanlash'),
      child: Material(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: 12),
            constraints: BoxConstraints(maxWidth: 150),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.calendar,
                  size: 16,
                  color: AppColors.primary,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Tor ekran uchun kichik alifbo almashtirgich ─────────────────────────────

class _ScriptMiniToggle extends StatelessWidget {
  const _ScriptMiniToggle();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppScript>(
      valueListenable: AppScriptController.instance,
      builder: (context, script, _) {
        final latin = script == AppScript.latin;
        return Tooltip(
          message: tr('Yozuv: lotin / kirill'),
          child: Material(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: AppScriptController.instance.toggle,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 36,
                padding: EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.translate_rounded,
                      size: 15,
                      color: AppColors.textSecondary,
                    ),
                    SizedBox(width: 4),
                    Text(
                      latin ? 'Lot' : 'Кир',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Holat filtri ────────────────────────────────────────────────────────────

/// To'q rangli (holat) fon ustidagi matn/ikonka rangi. Tungi rejimda
/// fon ranglari och (yashil/sariq) bo'lgani uchun oq emas, to'q rang olinadi.
Color _onFill() =>
    AppThemeController.instance.isDark ? AppColors.background : Colors.white;

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.provider});

  final AdminTasksProvider provider;

  @override
  Widget build(BuildContext context) {
    Widget statusChip(int status) {
      final selected = provider.selectedStatuses.contains(status);
      final color = statusColor(status);
      return _FilterChipButton(
        label: taskStatusLabel(status),
        selected: selected,
        color: color,
        leading: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: selected ? _onFill() : color,
            shape: BoxShape.circle,
          ),
        ),
        onTap: () => provider.toggleStatusFilter(status),
      );
    }

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        children: [
          statusChip(3),
          SizedBox(width: 8),
          statusChip(2),
          SizedBox(width: 8),
          statusChip(1),
          SizedBox(width: 8),
          _FilterChipButton(
            label: tr('Videosiz'),
            selected: provider.filterNoVideo,
            color: AppColors.textSecondary,
            leading: Icon(
              Icons.videocam_off_rounded,
              size: 15,
              color: provider.filterNoVideo
                  ? _onFill()
                  : AppColors.textSecondary,
            ),
            onTap: provider.toggleNoVideoFilter,
          ),
          if (provider.isFilterActive) ...[
            SizedBox(width: 4),
            TextButton.icon(
              onPressed: provider.clearStatusFilter,
              style: TextButton.styleFrom(
                minimumSize: Size(0, 34),
                padding: EdgeInsets.symmetric(horizontal: 10),
              ),
              icon: Icon(Icons.close_rounded, size: 16),
              label: Text(tr('Tozalash')),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.leading,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : AppColors.surface,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? color : AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: StadiumBorder(),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? _onFill() : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
