import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/ui/add_worker.dart';
import 'package:mone_task_app/admin/ui/user_edit_dialog.dart';
import 'package:mone_task_app/admin/service/user_service.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
import 'package:mone_task_app/home/model/login_model.dart';
import 'package:mone_task_app/home/service/api_service.dart';
import 'package:mone_task_app/home/ui/role_home.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:url_launcher/url_launcher.dart';

enum _UserAction { edit, role, filials, telegram, loginAs, delete }

class UsersPage extends StatefulWidget {
  final List<FilialModel> filialModel;
  const UsersPage({super.key, required this.filialModel});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  bool _loading = true;
  bool _error = false;
  List<UserModel> _users = [];
  List<FilialModel> _filials = [];
  final UserService _userService = UserService();

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _roleFilter; // null — barchasi
  int? _filialFilter; // null — barchasi

  @override
  void initState() {
    super.initState();
    _filials = widget.filialModel;
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final svc = TaskViewService();
      final results = await Future.wait([
        _userService.fetchUsers(),
        svc.fetchFilials(),
      ]);
      final users = results[0] as List<UserModel>;
      users.sort((a, b) => _roleOrder(a.role).compareTo(_roleOrder(b.role)));
      if (mounted) {
        setState(() {
          _users = users;
          _filials = results[1] as List<FilialModel>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _users.isEmpty;
        });
      }
    }
  }

  int _roleOrder(String role) {
    switch (role) {
      case 'super_admin':
        return 0;
      case 'checker':
        return 1;
      case 'worker':
        return 2;
      default:
        return 3;
    }
  }

  bool get _isSuperAdmin =>
      sl<TokenStorage>().getUserData()?.role == 'super_admin';

  String _filialName(int id) {
    final f = _filials.where((f) => f.filialId == id);
    return f.isNotEmpty ? displayName(f.first.name) : '#$id';
  }

  String _nameOf(UserModel u) =>
      u.fullName.isNotEmpty ? trData(u.fullName) : trData(u.username);

  List<UserModel> get _visibleUsers {
    final q = _query.trim().toLowerCase();
    return _users.where((u) {
      if (_roleFilter != null && u.role != _roleFilter) return false;
      if (_filialFilter != null &&
          !(u.filialIds ?? []).contains(_filialFilter)) {
        return false;
      }
      if (q.isEmpty) return true;
      final hay = [
        u.fullName,
        trData(u.fullName),
        u.username,
        trData(u.username),
        u.login,
        u.phoneNumber ?? '',
        u.telegram ?? '',
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  // ── Amallar ────────────────────────────────────────────────────────────

  Future<void> _deleteUser(UserModel u) async {
    final confirm = await showConfirmDialog(
      context,
      title: tr("Foydalanuvchini o'chirish"),
      message:
          '${_nameOf(u)} — ${tr("Ishonchingiz komilmi? Bu amalni ortga qaytarib bo'lmaydi.")}',
      confirmLabel: tr("Ha, o'chirish"),
      destructive: true,
    );
    if (!confirm) return;
    final success = await _userService.deleteUser(u.userId);
    if (!mounted) return;
    if (success) {
      showAppSnack(
        context,
        tr("Foydalanuvchi o'chirildi"),
        type: SnackType.success,
      );
      _load();
    } else {
      showAppSnack(
        context,
        tr("O'chirib bo'lmadi. Qayta urinib ko'ring."),
        type: SnackType.error,
      );
    }
  }

  Future<void> _callPhone(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: digits);
    await launchUrl(uri);
  }

  String _cleanError(Object e) => e.toString().replaceFirst('Exception: ', '');

  /// Bitta foydalanuvchiga login ma'lumotlarini (ism + login + parol + ilova
  /// linklari) Telegram orqali yuboradi. Avval tasdiqlash so'raladi.
  Future<void> _sendCredentials(UserModel u) async {
    final ok = await showConfirmDialog(
      context,
      title: tr('Telegram orqali yuborish'),
      message:
          '${_nameOf(u)} — ${tr('login va parol Telegram orqali yuborilsinmi?')}',
      confirmLabel: tr('Yuborish'),
    );
    if (!ok || !mounted) return;
    showAppSnack(context, tr('Yuborilmoqda...'));
    try {
      await _userService.sendCredentials(u.userId);
      if (!mounted) return;
      showAppSnack(
        context,
        tr('Telegram orqali yuborildi'),
        type: SnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, trData(_cleanError(e)), type: SnackType.error);
    }
  }

  /// super_admin'dan boshqa barcha foydalanuvchilarga login ma'lumotlarini
  /// (ism + login + parol + ilova linklari) bittada Telegram orqali yuboradi.
  Future<void> _sendAllCredentials() async {
    final ok = await showConfirmDialog(
      context,
      title: tr('Hammaga yuborish'),
      message: tr(
        'Barcha foydalanuvchilarga login va parol Telegram orqali yuborilsinmi?',
      ),
      confirmLabel: tr('Yuborish'),
    );
    if (!ok || !mounted) return;
    showAppSnack(context, tr('Yuborilmoqda...'));
    try {
      final res = await _userService.sendAllCredentials();
      if (!mounted) return;
      final sent = (res['sent'] as num?)?.toInt() ?? 0;
      final skipped = (res['skipped'] as List?)?.length ?? 0;
      final failed = (res['failed'] as List?)?.length ?? 0;
      final parts = <String>['$sent ${tr('ta yuborildi')}'];
      if (skipped > 0) parts.add('$skipped ${tr('ta Telegramsiz')}');
      if (failed > 0) parts.add('$failed ${tr('ta xatolik')}');
      showAppSnack(
        context,
        parts.join(' · '),
        type: failed > 0 ? SnackType.error : SnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnack(
        context,
        '${tr('Xatolik')}: ${_cleanError(e)}',
        type: SnackType.error,
      );
    }
  }

  Future<void> _openAddUser() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddWorkerPage()),
    );
    if (result == true) _load();
  }

  void _onAction(UserModel u, _UserAction a) {
    switch (a) {
      case _UserAction.edit:
        _showEditDialog(u);
      case _UserAction.role:
        _pickRole(u);
      case _UserAction.filials:
        _pickFilials(u);
      case _UserAction.telegram:
        _sendCredentials(u);
      case _UserAction.loginAs:
        _loginAsUser(u);
      case _UserAction.delete:
        _deleteUser(u);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Foydalanuvchilar')),
        actions: [
          IconButton(
            tooltip: tr('Yangilash'),
            icon: Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
          // Barcha foydalanuvchilarga login ma'lumotlarini bittada Telegram
          // orqali yuborish — faqat super_admin ko'radi.
          if (_isSuperAdmin)
            PopupMenuButton<int>(
              tooltip: tr("Ko'proq"),
              icon: Icon(Icons.more_vert_rounded),
              onSelected: (_) => _sendAllCredentials(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 0,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.send_rounded),
                    title: Text(tr('Hammaga Telegram orqali yuborish')),
                  ),
                ),
              ],
            ),
          SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddUser,
        icon: Icon(Icons.person_add_alt_1_rounded),
        label: Text(tr('Yangi foydalanuvchi')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              _buildFilters(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final t = Theme.of(context).textTheme;
    final count = _loading && _users.isEmpty ? null : _visibleUsers.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: tr("Ism, login yoki telefon bo'yicha qidirish"),
              prefixIcon: Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: tr('Tozalash'),
                      icon: Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _roleChip(null, tr('Hammasi')),
                for (final r in kUserRoles) _roleChip(r, userRoleLabel(r)),
                SizedBox(width: 4),
                _filialFilterChip(),
              ],
            ),
          ),
          if (count != null)
            Padding(
              padding: EdgeInsets.only(top: 8, left: 4),
              child: Text(
                '$count ${tr('ta foydalanuvchi')}',
                style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _roleChip(String? role, String label) {
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _roleFilter == role,
        onSelected: (_) => setState(() => _roleFilter = role),
      ),
    );
  }

  Widget _filialFilterChip() {
    final active = _filialFilter != null;
    return PopupMenuButton<int>(
      tooltip: tr('Filial'),
      position: PopupMenuPosition.under,
      constraints: BoxConstraints(maxHeight: 420, minWidth: 220),
      onSelected: (id) => setState(() => _filialFilter = id < 0 ? null : id),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: -1,
          checked: _filialFilter == null,
          child: Text(tr('Barcha filiallar')),
        ),
        PopupMenuDivider(),
        ..._filials.map(
          (f) => CheckedPopupMenuItem(
            value: f.filialId,
            checked: _filialFilter == f.filialId,
            child: Text(displayName(f.name), overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      child: Chip(
        avatar: Icon(
          Icons.storefront_outlined,
          size: 18,
          color: active ? AppColors.primary : AppColors.textSecondary,
        ),
        label: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 180),
          child: Text(
            active ? _filialName(_filialFilter!) : tr('Filial'),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? AppColors.primary : AppColors.textPrimary,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
        backgroundColor: active ? AppColors.primarySoft : null,
        side: BorderSide(color: active ? AppColors.primary : AppColors.border),
        deleteIcon: active ? Icon(Icons.close_rounded, size: 16) : null,
        onDeleted: active ? () => setState(() => _filialFilter = null) : null,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _users.isEmpty) return AppLoader();
    if (_error) return AppErrorState(onRetry: _load);
    if (_users.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: 40),
            AppEmptyState(
              icon: Icons.people_outline_rounded,
              title: tr("Hali foydalanuvchilar yo'q"),
              message: tr(
                "Birinchi xodimni qo'shish uchun «Yangi foydalanuvchi» tugmasini bosing.",
              ),
              actionLabel: tr('Yangi foydalanuvchi'),
              onAction: _openAddUser,
            ),
          ],
        ),
      );
    }
    final users = _visibleUsers;
    if (users.isEmpty) {
      return AppEmptyState(
        icon: Icons.search_off_rounded,
        title: tr('Hech narsa topilmadi'),
        message: tr("Qidiruv so'zini yoki filtrlarni o'zgartirib ko'ring."),
        actionLabel: tr('Filtrlarni tozalash'),
        onAction: () {
          _searchController.clear();
          setState(() {
            _query = '';
            _roleFilter = null;
            _filialFilter = null;
          });
        },
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: users.length,
        separatorBuilder: (_, __) => SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, i) => _userCard(users[i]),
      ),
    );
  }

  // ── Foydalanuvchi kartasi ──────────────────────────────────────────────

  Widget _userCard(UserModel u) {
    final t = Theme.of(context).textTheme;
    final phone = u.phoneNumber ?? '';
    final tg = u.telegram;
    final pos = u.position;
    final filialIds = u.filialIds ?? <int>[];
    final allFilials = u.role == 'super_admin' || u.role == 'checker';

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showEditDialog(u),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(u),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nameOf(u).isNotEmpty ? _nameOf(u) : '—',
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _roleBadge(u.role),
                        if (u.login.isNotEmpty)
                          Text(
                            '@${u.login}',
                            style: t.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    if (pos != null && pos.isNotEmpty)
                      _infoLine(Icons.work_outline_rounded, trData(pos)),
                    if (phone.isNotEmpty)
                      _infoLine(
                        Icons.phone_outlined,
                        phone,
                        link: true,
                        onTap: () => _callPhone(phone),
                      ),
                    if (u.password.isNotEmpty)
                      _infoLine(Icons.key_rounded, u.password),
                    if (tg != null && tg.isNotEmpty)
                      _infoLine(
                        Icons.send_outlined,
                        '@$tg',
                        link: true,
                        onTap: () => _openTelegram(tg),
                      ),
                    if (allFilials)
                      _infoLine(
                        Icons.storefront_outlined,
                        tr('Barcha filiallar'),
                      )
                    else if (filialIds.isEmpty)
                      _infoLine(
                        Icons.storefront_outlined,
                        tr('Filial tanlanmagan'),
                        warning: true,
                        onTap: () => _pickFilials(u),
                      )
                    else
                      _infoLine(
                        Icons.storefront_outlined,
                        filialIds.map(_filialName).join(', '),
                        onTap: () => _pickFilials(u),
                        maxLines: 2,
                      ),
                  ],
                ),
              ),
              _actionsMenu(u),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionsMenu(UserModel u) {
    final canSend = u.role != 'super_admin' && _isSuperAdmin;
    PopupMenuItem<_UserAction> item(
      _UserAction a,
      IconData icon,
      String label, {
      bool danger = false,
    }) {
      final color = danger ? AppColors.danger : AppColors.textPrimary;
      return PopupMenuItem(
        value: a,
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: danger ? color : AppColors.textSecondary,
            ),
            SizedBox(width: 12),
            Flexible(
              child: Text(label, style: TextStyle(color: color)),
            ),
          ],
        ),
      );
    }

    return PopupMenuButton<_UserAction>(
      tooltip: tr('Amallar'),
      icon: Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
      onSelected: (a) => _onAction(u, a),
      itemBuilder: (_) => [
        item(_UserAction.edit, Icons.edit_outlined, tr('Tahrirlash')),
        if (u.role != 'super_admin')
          item(
            _UserAction.role,
            Icons.badge_outlined,
            tr("Rolni o'zgartirish"),
          ),
        if (u.role == 'worker')
          item(
            _UserAction.filials,
            Icons.storefront_outlined,
            tr('Filiallarni tanlash'),
          ),
        if (canSend)
          item(
            _UserAction.telegram,
            Icons.send_rounded,
            tr('Telegram orqali yuborish'),
          ),
        item(
          _UserAction.loginAs,
          Icons.login_rounded,
          tr('Shu foydalanuvchi sifatida kirish'),
        ),
        PopupMenuDivider(),
        item(
          _UserAction.delete,
          Icons.delete_outline_rounded,
          tr("O'chirish"),
          danger: true,
        ),
      ],
    );
  }

  Widget _avatar(UserModel u) {
    final imgUrl = u.photoUrl ?? '';
    final name = _nameOf(u).trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return GestureDetector(
      onTap: imgUrl.isNotEmpty ? () => _showAvatarPreview(imgUrl, name) : null,
      child: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primarySoft,
        foregroundImage: imgUrl.isNotEmpty ? NetworkImage(imgUrl) : null,
        onForegroundImageError: imgUrl.isNotEmpty ? (_, __) {} : null,
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _infoLine(
    IconData icon,
    String text, {
    bool link = false,
    bool warning = false,
    VoidCallback? onTap,
    int maxLines = 1,
  }) {
    final color = warning
        ? AppColors.warning
        : link
        ? AppColors.primary
        : AppColors.textSecondary;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            icon,
            size: 15,
            color: warning ? color : AppColors.textTertiary,
          ),
        ),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: link || warning ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(top: 6),
      child: onTap == null
          ? row
          : InkWell(onTap: onTap, borderRadius: AppRadius.smAll, child: row),
    );
  }

  Widget _roleBadge(String role) {
    final (fg, bg) = userRoleColors(role);
    return StatusBadge(label: userRoleLabel(role), color: fg, background: bg);
  }

  // ── Rolni o'zgartirish ─────────────────────────────────────────────────

  Future<void> _pickRole(UserModel u) async {
    final next = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                tr("Rolni o'zgartirish"),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final r in ['checker', 'worker'])
              ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 24),
                title: Text(userRoleLabel(r)),
                subtitle: Text(
                  r == 'checker'
                      ? tr("Barcha filiallarni ko'radi va tekshiradi")
                      : tr('Faqat tanlangan filiallar bilan ishlaydi'),
                ),
                trailing: u.role == r
                    ? Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, r),
              ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (next == null) return;
    await _changeRole(u, next);
  }

  Future<void> _changeRole(UserModel u, String next) async {
    if (next == u.role) return;
    final success = await _userService.updateUser(
      userId: u.userId,
      username: u.username,
      role: next,
      filialIds: u.filialIds,
    );
    if (!mounted) return;
    if (success) {
      showAppSnack(context, tr('Yangilandi'), type: SnackType.success);
      _load();
    } else {
      showAppSnack(
        context,
        tr("Saqlab bo'lmadi. Qayta urinib ko'ring."),
        type: SnackType.error,
      );
    }
  }

  // ── Filiallarni tanlash ────────────────────────────────────────────────

  Future<void> _pickFilials(UserModel u) async {
    final initial = Set<int>.from(u.filialIds ?? <int>[]);
    final selected = Set<int>.from(initial);

    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 4),
                  child: Text(
                    tr('Filiallarni tanlash'),
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    _nameOf(u),
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_filials.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(tr("Filiallar yo'q")),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: _filials.map((f) {
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.symmetric(horizontal: 16),
                          controlAffinity: ListTileControlAffinity.leading,
                          value: selected.contains(f.filialId),
                          title: Text(displayName(f.name)),
                          onChanged: (v) => setS(() {
                            v == true
                                ? selected.add(f.filialId)
                                : selected.remove(f.filialId);
                          }),
                        );
                      }).toList(),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(tr('Saqlash')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (save != true) return;
    if (selected.length == initial.length && selected.containsAll(initial)) {
      return;
    }
    // Server bo'sh ro'yxatni qabul qilmaydi (eski filiallar qolib ketadi) —
    // shuning uchun kamida bitta filial talab qilinadi.
    if (selected.isEmpty) {
      if (!mounted) return;
      showAppSnack(
        context,
        tr('Kamida bitta filialni tanlang'),
        type: SnackType.error,
      );
      return;
    }
    final success = await _userService.updateUser(
      userId: u.userId,
      username: u.username,
      role: u.role,
      filialIds: selected.toList(),
    );
    if (!mounted) return;
    if (success) {
      showAppSnack(context, tr('Yangilandi'), type: SnackType.success);
      _load();
    } else {
      showAppSnack(
        context,
        tr("Saqlab bo'lmadi. Qayta urinib ko'ring."),
        type: SnackType.error,
      );
    }
  }

  // ── Tahrirlash dialogi ─────────────────────────────────────────────────

  Future<void> _showEditDialog(UserModel u) async {
    final saved = await UserEditDialog.show(
      context,
      user: u,
      filials: _filials,
    );
    if (saved == true) _load();
  }

  // ── O'sha foydalanuvchi paroli bilan kirish ────────────────────────────

  Future<void> _loginAsUser(UserModel u) async {
    if (u.password.isEmpty) {
      showAppSnack(
        context,
        tr("Bu foydalanuvchida parol yo'q"),
        type: SnackType.error,
      );
      return;
    }

    final result = await ApiService().login(LoginModel(password: u.password));
    if (!mounted) return;

    if (result['success'] == true && result['token'] != null) {
      final ts = sl<TokenStorage>();
      await ts.putToken(result['token']);
      await ts.putUserData(Map<String, dynamic>.from(result['user'] as Map));
      if (!mounted) return;
      context.pushAndRemove(
        landingForUser(
          UserModel.fromJson(Map<String, dynamic>.from(result['user'] as Map)),
        ),
      );
    } else {
      final serverMsg =
          result['message']?.toString() ?? result['error']?.toString();
      showAppSnack(
        context,
        serverMsg != null && serverMsg.isNotEmpty
            ? trData(serverMsg)
            : tr("Kirib bo'lmadi"),
        type: SnackType.error,
      );
    }
  }

  // ── Yordamchilar ───────────────────────────────────────────────────────

  Future<void> _openTelegram(String username) async {
    final appUri = Uri.parse('tg://resolve?domain=$username');
    final webUri = Uri.parse('https://t.me/$username');
    try {
      if (await canLaunchUrl(appUri)) {
        final ok = await launchUrl(
          appUri,
          mode: LaunchMode.externalApplication,
        );
        if (ok) return;
      }
    } catch (_) {}
    try {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _showAvatarPreview(String url, String name) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(24),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: ClipRRect(
                  borderRadius: AppRadius.lgAll,
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                    errorBuilder: (_, __, ___) => Container(
                      width: 320,
                      height: 320,
                      color: Colors.black26,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: Colors.black54,
                shape: CircleBorder(),
                child: IconButton(
                  tooltip: tr('Yopish'),
                  onPressed: () => Navigator.pop(ctx),
                  icon: Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
            if (name.isNotEmpty)
              Positioned(
                left: 16,
                bottom: 16,
                right: 16,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
