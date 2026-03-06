import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/provider/admin_task_list_widget.dart';
import 'package:mone_task_app/admin/provider/admin_tasks_provider.dart';
import 'package:mone_task_app/admin/provider/circle_video_player.dart';
import 'package:mone_task_app/admin/provider/my_drawer.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/login_service.dart';
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
  }

  @override
  void dispose() {
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
    List<CheckerCheckTaskModel> tasks,
  ) {
    if (videoPaths.isEmpty) return;
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
        ),
      ),
    );
  }

  Future<void> _handleDateSelection() async {
    // Provider dan olamiz — setState ishlatmaymiz
    final provider = context.read<AdminTasksProvider>();
    final currentDate = provider.selectedDate;

    // showDatePicker ni await qilamiz — bu paytda widget rebuild bo'lmaydi
    final DateTime? picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      initialDate: currentDate,
      lastDate: DateTime.now(),
    );

    // Dialog to'liq yopilgandan KEYIN provider yangilanadi
    // setState ISHLATMAYMIZ — shu bug ning sababi edi
    if (picked != null && mounted) {
      provider.setSelectedDate(picked);
    }
  }

  Future<void> _handleLogout() async {
    await LogOutService().logOut();
    _tokenStorage.removeToken();
    _tokenStorage.putUserData({});
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
                'Kategoriyalarni yuklashda xatolik:\n${tasksProvider.filialsError}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => tasksProvider.fetchFilials(),
                child: const Text('Qayta urinish'),
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
        body: const Center(child: Text("Hech qanday filial topilmadi")),
      );
    }

    final categories = tasksProvider.filials;
    _initTabController(categories.length);

    return Scaffold(
      drawer: MyDrawer(
        categories: categories,
        user: _user,
        onLogout: _handleLogout,
      ),
      appBar: AppBar(
        title: Text(_user?.username ?? ""),
        actions: [
          // ── Status filter tugmalari ────────────────────────────────────
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

          // ── Filterni tozalash ──────────────────────────────────────────
          if (tasksProvider.isFilterActive)
            IconButton(
              onPressed: () => tasksProvider.clearStatusFilter(),
              icon: const Icon(Icons.filter_alt_off, size: 20),
              tooltip: 'Filterni tozalash',
            ),

          // ── Sana tanlash ───────────────────────────────────────────────
          GestureDetector(
            onTap: _handleDateSelection,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  selectedDate.day == DateTime.now().day
                      ? "Сегодня"
                      : "${selectedDate.day}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}",
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          padding: EdgeInsets.zero,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: categories.map((c) => Tab(text: c.name)).toList(),
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
              'Xatolik: ${tasksProvider.tasksError}',
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
      return const Center(child: Text("Hech qanday task topilmadi"));
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

    return GestureDetector(
      onTap: () => provider.toggleStatusFilter(status),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? color : color.withOpacity(0.2),
            border: Border.all(
              color: isSelected ? color : color.withOpacity(0.4),
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6)]
                : [],
          ),
          child: isSelected
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
