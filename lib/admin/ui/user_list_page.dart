import 'package:flutter/material.dart';
import 'package:mone_task_app/shared/widgets/profile_switch_button.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/ui/add_worker.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart'
    show TemplateService;
import 'package:mone_task_app/admin/service/user_service.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/shared/widgets/switch_chip.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:url_launcher/url_launcher.dart';

class UsersPage extends StatefulWidget {
  final List<FilialModel> filialModel;
  const UsersPage({super.key, required this.filialModel});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  bool _loading = true;
  List<UserModel> _users = [];
  List<FilialModel> _filials = [];
  List<CategoryModel> _categories = [];
  final UserService _userService = UserService();
  bool _profileView = false;
  // Filial/kategoriya switchlari ochilgan foydalanuvchilar (qolganlari ixcham).
  final Set<int> _expandedUsers = {};
  // Paroli shu yerning o'zida tahrirlanayotgan foydalanuvchi.
  int? _editingPasswordFor;
  bool _savingPassword = false;
  final TextEditingController _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final svc = TaskViewService();
      final results = await Future.wait([
        _userService.fetchUsers(),
        svc.fetchFilials(),
        TemplateService().fetchCategoriesList(),
      ]);
      final users = results[0] as List<UserModel>;
      users.sort((a, b) => _roleOrder(a.role).compareTo(_roleOrder(b.role)));
      if (mounted) {
        setState(() {
          _users = users;
          _filials = results[1] as List<FilialModel>;
          _categories = results[2] as List<CategoryModel>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
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
      case 'sotrudnik':
        return 3;
      default:
        return 4;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'super_admin':
        return 'Супер админ';
      case 'checker':
        return 'Корректор';
      case 'worker':
        return 'Ревизор';
      case 'sotrudnik':
        return 'Сотрудник';
      default:
        return role;
    }
  }

  bool _isMe(UserModel u) =>
      sl<TokenStorage>().getUserData()?.userId == u.userId;

  Future<void> _deleteUser(int id) async {
    if (sl<TokenStorage>().getUserData()?.userId == id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нельзя удалить самого себя'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить'),
        content: const Text(
          'Вы уверены, что хотите удалить этого пользователя?',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final success = await _userService.deleteUser(id);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось удалить'),
          backgroundColor: Colors.red,
        ),
      );
    }
    if (success) {
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Пользователь удалён'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _callPhone(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: digits);
    await launchUrl(uri);
  }

  // ── Build ──────────────────────────────────────────────────────────────

  /// Bitta foydalanuvchiga login ma'lumotlarini (ism + login + parol + ilova
  /// linklari) Telegram orqali yuboradi. Avval tasdiqlash so'raladi.
  Future<void> _sendCredentials(UserModel u) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = u.fullName.isNotEmpty ? u.fullName : u.username;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Отправить в Telegram'),
        content: Text('$name — отправить логин и пароль через Telegram?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    messenger.showSnackBar(const SnackBar(content: Text('Отправляется...')));
    try {
      await _userService.sendCredentials(u.userId);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Отправлено в Telegram'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      final msg = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  /// super_admin'dan boshqa barcha foydalanuvchilarga login ma'lumotlarini
  /// (ism + login + parol + ilova linklari) bittada Telegram orqali yuboradi.
  /// Avval tasdiqlash so'raladi, so'ng natija snackbar'da ko'rsatiladi.
  Future<void> _sendAllCredentials() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Отправить всем'),
        content: const Text(
          'Отправить логин и пароль всем пользователям через Telegram?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    messenger.showSnackBar(const SnackBar(content: Text('Отправляется...')));
    try {
      final res = await _userService.sendAllCredentials();
      if (!mounted) return;
      final sent = (res['sent'] as num?)?.toInt() ?? 0;
      final skipped = (res['skipped'] as List?)?.length ?? 0;
      final failed = (res['failed'] as List?)?.length ?? 0;
      final parts = <String>['$sent отправлено'];
      if (skipped > 0) parts.add('$skipped без Telegram');
      if (failed > 0) parts.add('$failed ошибок');
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(parts.join(' · ')),
          backgroundColor: failed > 0 ? Colors.orange : Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin =
        sl<TokenStorage>().getUserData()?.role == 'super_admin';
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Пользователи'),
        actions: [
          // Barcha foydalanuvchilarga login ma'lumotlarini bittada Telegram
          // orqali yuborish — faqat super_admin ko'radi.
          if (isSuperAdmin)
            IconButton(
              icon: const Icon(Icons.send_rounded),
              tooltip: 'Отправить всем в Telegram',
              onPressed: _sendAllCredentials,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      '${_users.length} пользователей',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const Spacer(),
                    _viewToggleButton(),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddWorkerPage(),
                          ),
                        );
                        if (result == true) _load();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Новый'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: _load,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (!_profileView) ...[
                Container(
                  color: const Color(0xFFF9FAFB),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      _th('#', 36),
                      const SizedBox(width: 60),
                      _thFlex('Имя', 2),
                      _th('Роль', 140),
                      _thFlex('Филиалы', 2),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _users.isEmpty
                    ? const Center(child: Text('Пользователи не найдены'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _profileView ? _profileGrid() : _listView(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── View toggle ────────────────────────────────────────────────────────

  Widget _viewToggleButton() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleSeg(
            icon: Icons.view_list_rounded,
            label: 'Список',
            selected: !_profileView,
            onTap: () => setState(() => _profileView = false),
          ),
          _toggleSeg(
            icon: Icons.account_box_rounded,
            label: 'Профиль',
            selected: _profileView,
            onTap: () => setState(() => _profileView = true),
          ),
        ],
      ),
    );
  }

  Widget _toggleSeg({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(0xFF111827)
                    : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── List view ──────────────────────────────────────────────────────────

  Widget _listView() {
    return ListView.separated(
      itemCount: _users.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _row(_users[i], i + 1),
    );
  }

  Widget _th(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _thFlex(String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _row(UserModel u, int index) {
    final phone = u.phoneNumber ?? u.login;
    final imgUrl = u.photoUrl ?? '';
    // Ochilgan holatda rol yozuvi parol tagiga tushadi, «Роль» ustuni
    // yo'qoladi va filial/kategoriya paneli kengroq joy oladi.
    final expanded = _expandedUsers.contains(u.userId);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _deleteUser(u.userId),
      onDoubleTap: () => _loginAsUser(u),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                '$index',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ),
            SizedBox(
              width: 60,
              child: GestureDetector(
                onTap: imgUrl.isNotEmpty
                    ? () => _showAvatarPreview(imgUrl, u.fullName)
                    : null,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE0E7FF),
                    border: Border.all(
                      color: const Color(0xFFE5E7EB),
                      width: 1,
                    ),
                    image: imgUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(imgUrl),
                            fit: BoxFit.cover,
                            onError: (_, __) {},
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: imgUrl.isEmpty
                      ? Text(
                          u.fullName.trim().isNotEmpty
                              ? u.fullName.trim()[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3730A3),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    u.fullName.isNotEmpty ? u.fullName : '—',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF111827),
                    ),
                    maxLines: expanded ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _callPhone(phone),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.phone_rounded,
                            size: 14,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              phone,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2563EB),
                                decoration: TextDecoration.underline,
                                decorationColor: Color(0xFF2563EB),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (u.password.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _passwordLine(u),
                  ],
                  if (expanded) ...[const SizedBox(height: 4), _roleBadge(u)],
                ],
              ),
            ),
            if (!expanded)
              SizedBox(
                width: 140,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _roleBadge(u),
                ),
              ),
            Expanded(flex: expanded ? 3 : 2, child: _filialSwitchGrid(u)),
            // Bitta foydalanuvchiga login ma'lumotlarini Telegram orqali yuborish.
            if (u.role != 'super_admin' &&
                sl<TokenStorage>().getUserData()?.role == 'super_admin')
              IconButton(
                tooltip: 'Отправить в Telegram',
                icon: const Icon(
                  Icons.send_rounded,
                  size: 20,
                  color: Color(0xFF2563EB),
                ),
                onPressed: () => _sendCredentials(u),
              ),
            if (sl<TokenStorage>().getUserData()?.role == 'super_admin')
              IconButton(
                tooltip: 'Удалить',
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: _isMe(u) ? const Color(0xFFD1D5DB) : Colors.red,
                ),
                onPressed: _isMe(u) ? null : () => _deleteUser(u.userId),
              ),
          ],
        ),
      ),
    );
  }

  // ── Filial ruxsatlari (switch) ─────────────────────────────────────────

  /// Har filial uchun «nom + switch» — 2 ustunli setka. Switch bosilishi
  /// bilan ruxsat darhol beriladi / yopiladi (serverga saqlanadi).
  Widget _filialSwitchGrid(UserModel u) {
    // super_admin va checker (Корректор) barcha filiallarni ko'radi —
    // filial ruxsati kerak emas.
    if (u.role == 'super_admin' || u.role == 'checker') {
      return Text('—', style: TextStyle(fontSize: 13, color: Colors.grey[400]));
    }
    if (_filials.isEmpty) {
      return Text(
        'Филиалов нет',
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
      );
    }
    final canMutate = sl<TokenStorage>().getUserData()?.role == 'super_admin';
    final ids = u.filialIds ?? const <int>[];

    if (!_expandedUsers.contains(u.userId)) return _accessSummary(u);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _expandedUsers.remove(u.userId)),
            icon: const Icon(Icons.expand_less_rounded, size: 18),
            label: const Text('Свернуть'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        // «Задачи» — o'z filiallari uchun vazifa qo'shish/tahrirlash/o'chirish ruxsati.
        SwitchChip(
          label: 'Задачи (добавлять / изменять / удалять)',
          value: u.canManageTasks,
          onChanged: canMutate ? (v) => _toggleManageTasks(u, v) : null,
        ),
        const SizedBox(height: 10),
        SwitchChipGrid(
          // Bosib turib sudrash — filiallar tartibi (hamma joyda bir xil)
          onReorder: canMutate ? _reorderFilials : null,
          children: [
            for (final f in _filials)
              SwitchChip(
                label: f.name,
                value: ids.contains(f.filialId),
                count: _accessCount(f.filialId),
                onChanged: canMutate
                    ? (v) => _toggleFilial(u, f.filialId, v)
                    : null,
              ),
          ],
        ),
        // Kategoriyalar — faqat worker uchun (tahrirlash oynasidagi kabi).
        if (u.role == 'worker' && _categories.isNotEmpty) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Категории',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchChipGrid(
            children: [
              for (final c in _categories)
                SwitchChip(
                  label: c.name,
                  value: u.categories?.contains(c.name) ?? false,
                  count: _categoryCount(c.name),
                  onChanged: canMutate
                      ? (v) => _toggleCategory(u, c.name, v)
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Ixcham ko'rinish: faqat yoqilgan filial/kategoriyalar kichik teglar
  /// bilan. Bosilsa — to'liq switchlar ochiladi.
  Widget _accessSummary(UserModel u) {
    final ids = u.filialIds ?? const <int>[];
    final filials = _filials.where((f) => ids.contains(f.filialId));
    final categories = u.role == 'worker'
        ? (u.categories ?? const <String>[])
        : const <String>[];

    Widget tag(String text, Color fg, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );

    // Har guruh alohida qatorda, chapda ikonka + nom bilan — filial va
    // kategoriyalar aralashib ketmasligi uchun.
    Widget section(IconData icon, String title, Color fg, List<Widget> items) =>
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    Icon(icon, size: 14, color: fg),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: items)),
          ],
        );

    const filialFg = Color(0xFF15803D);
    const categoryFg = Color(0xFF1D4ED8);
    final sections = <Widget>[
      if (u.canManageTasks)
        section(Icons.task_alt_rounded, 'Права', const Color(0xFF7C3AED), [
          tag('Задачи', const Color(0xFF7C3AED), const Color(0xFFF3E8FF)),
        ]),
      if (filials.isNotEmpty)
        section(Icons.store_rounded, 'Филиалы', filialFg, [
          for (final f in filials)
            tag(f.name, filialFg, const Color(0xFFDCFCE7)),
        ]),
      if (categories.isNotEmpty)
        section(Icons.badge_outlined, 'Категории', categoryFg, [
          for (final c in categories)
            tag(c, categoryFg, const Color(0xFFDBEAFE)),
        ]),
    ];

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _expandedUsers.add(u.userId)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: sections.isEmpty
                  ? Text(
                      'Нет доступа',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < sections.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 13, color: Color(0xFFF1F5F9)),
                          sections[i],
                        ],
                      ],
                    ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.expand_more_rounded, size: 20, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }

  /// Nechta xodimda shu filialga ruxsat yoqilgan (super_admin va checker
  /// hamma filialni ko'radi — ular sanalmaydi).
  int _accessCount(int filialId) => _users
      .where(
        (u) =>
            u.role != 'super_admin' &&
            u.role != 'checker' &&
            (u.filialIds?.contains(filialId) ?? false),
      )
      .length;

  /// Shu kategoriya yoqilgan xodimlar soni (kategoriya faqat worker uchun).
  int _categoryCount(String name) => _users
      .where(
        (u) => u.role == 'worker' && (u.categories?.contains(name) ?? false),
      )
      .length;

  /// Optimistik: tartib darhol o'zgaradi va serverga saqlanadi — tablar va
  /// boshqa sahifalar ham shu tartibni oladi. Xato bo'lsa orqaga qaytadi.
  Future<void> _reorderFilials(int from, int to) async {
    final previous = _filials;
    final next = List<FilialModel>.from(_filials);
    next.insert(to, next.removeAt(from));
    setState(() => _filials = next);

    final ok = await TemplateService().reorderFilials(
      next.map((f) => f.filialId).toList(),
    );
    if (!mounted || ok) return;
    setState(() => _filials = previous);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Не удалось сохранить порядок'),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// Optimistik: switch darhol o'zgaradi, server xato qaytarsa orqaga qaytadi.
  Future<void> _toggleFilial(UserModel u, int filialId, bool on) async {
    final next = List<int>.from(u.filialIds ?? const <int>[]);
    on ? next.add(filialId) : next.remove(filialId);
    _replaceUser(u.copyWith(filialIds: next));

    final success = await _userService.updateUser(
      userId: u.userId,
      username: u.username,
      role: u.role,
      filialIds: next,
      // Kategoriyalar o'chib ketmasligi uchun mavjudini qayta yuboramiz.
      categories: u.categories,
    );
    if (!mounted) return;
    if (!success) {
      _replaceUser(u);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось сохранить'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Optimistik: kategoriya switch darhol o'zgaradi, xato bo'lsa orqaga qaytadi.
  Future<void> _toggleCategory(UserModel u, String name, bool on) async {
    final next = List<String>.from(u.categories ?? const <String>[]);
    on ? next.add(name) : next.remove(name);
    _replaceUser(u.copyWith(categories: next));

    final success = await _userService.updateUser(
      userId: u.userId,
      username: u.username,
      role: u.role,
      filialIds: u.filialIds,
      categories: next,
    );
    if (!mounted) return;
    if (!success) {
      _replaceUser(u);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось сохранить'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Optimistik: «Задачи» ruxsati darhol o'zgaradi, xato bo'lsa orqaga qaytadi.
  Future<void> _toggleManageTasks(UserModel u, bool on) async {
    _replaceUser(u.copyWith(canManageTasks: on));

    final success = await _userService.updateUser(
      userId: u.userId,
      username: u.username,
      role: u.role,
      filialIds: u.filialIds,
      categories: u.categories,
      canManageTasks: on,
    );
    if (!mounted) return;
    if (!success) {
      _replaceUser(u);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось сохранить'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _replaceUser(UserModel u) {
    setState(() {
      final i = _users.indexWhere((x) => x.userId == u.userId);
      if (i != -1) _users[i] = u;
    });
  }

  // ── Profile grid view ──────────────────────────────────────────────────

  Widget _profileGrid() {
    if (_users.isEmpty) {
      return Center(
        child: Text(
          'Пользователей нет',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }
    return LayoutBuilder(
      builder: (ctx, c) {
        final isWide = c.maxWidth >= 600;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _users.length,
          itemBuilder: (_, i) => _profileCard(_users[i], isWide: isWide),
        );
      },
    );
  }

  Widget _profileCard(UserModel u, {required bool isWide}) {
    final cardContent = Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _userImage(u, isWide: isWide),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: isWide ? _userFullFields(u) : _userShortFields(u),
            ),
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _deleteUser(u.userId),
            onDoubleTap: () => _loginAsUser(u),
            child: cardContent,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _userImage(UserModel u, {required bool isWide}) {
    final w = isWide ? 200.0 : 130.0;
    final h = isWide ? 260.0 : 180.0;
    final imgRaw = u.photoUrl ?? '';
    if (imgRaw.isNotEmpty) {
      return GestureDetector(
        onTap: () => _showAvatarPreview(imgRaw, u.fullName),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            imgRaw,
            width: w,
            height: h,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.person, size: 40, color: Colors.grey[400]),
            ),
          ),
        ),
      );
    }
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFFE0E7FF),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: w * 0.3,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF3730A3),
        ),
      ),
    );
  }

  List<Widget> _userShortFields(UserModel u) {
    final phone = u.phoneNumber ?? u.login;
    final tg = u.telegram;
    return [
      _userCardHeader(u),
      _phoneLine(phone),
      if (u.password.isNotEmpty) _passwordLine(u),
      if (tg != null && tg.isNotEmpty) _telegramLine(tg),
      if (u.filialIds != null && u.filialIds!.isNotEmpty)
        _profileInfoLine(
          Icons.location_on_outlined,
          _filialNames(u.filialIds!),
        ),
    ];
  }

  List<Widget> _userFullFields(UserModel u) {
    final phone = u.phoneNumber ?? u.login;
    final pos = u.position;
    final tg = u.telegram;
    return [
      _userCardHeader(u),
      if (pos != null && pos.isNotEmpty)
        _profileInfoLine(Icons.work_outlined, pos),
      _phoneLine(phone),
      if (u.password.isNotEmpty) _passwordLine(u),
      if (tg != null && tg.isNotEmpty) _telegramLine(tg),
      if (u.filialIds != null && u.filialIds!.isNotEmpty)
        _profileInfoLine(
          Icons.location_on_outlined,
          _filialNames(u.filialIds!),
        ),
    ];
  }

  /// Filial nomlari — umumiy filial tartibida (tablardagi kabi).
  String _filialNames(List<int> ids) {
    final names = [
      for (final f in _filials)
        if (ids.contains(f.filialId)) f.name,
    ];
    final known = _filials.map((f) => f.filialId).toSet();
    names.addAll(ids.where((id) => !known.contains(id)).map((id) => '#$id'));
    return names.join(', ');
  }

  Widget _userCardHeader(UserModel u) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  u.fullName.isNotEmpty ? u.fullName : '—',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _roleBadge(u),
            ],
          ),
          if (u.position != null && u.position!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              u.position!,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _profileInfoLine(IconData icon, String text, {int? maxLines}) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: Colors.grey[400]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              maxLines: maxLines,
              overflow: maxLines != null
                  ? TextOverflow.ellipsis
                  : TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneLine(String telefon) {
    if (telefon.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: () => _callPhone(telefon),
        child: Row(
          children: [
            Icon(Icons.phone_outlined, size: 14, color: Colors.grey[400]),
            const SizedBox(width: 8),
            Text(
              telefon,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF3699ff),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Parol — kattaroq, kulrang "pill" ichida. Super admin bossa — shu
  /// yerning o'zida tahrirlanadi (Enter — saqlash, ✕ — bekor qilish).
  Widget _passwordLine(UserModel u) {
    final editing = _editingPasswordFor == u.userId;
    final canEdit = sl<TokenStorage>().getUserData()?.role == 'super_admin';
    const textStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: Color(0xFF111827),
    );

    final pill = Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: editing ? 2 : 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(8),
        border: editing ? Border.all(color: const Color(0xFF2563EB)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.key_rounded, size: 16, color: Color(0xFF2563EB)),
          const SizedBox(width: 8),
          if (editing) ...[
            SizedBox(
              width: 140,
              child: TextField(
                controller: _passwordCtrl,
                autofocus: true,
                enabled: !_savingPassword,
                style: textStyle,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                ),
                onSubmitted: (_) => _savePassword(u),
              ),
            ),
            if (_savingPassword)
              const Padding(
                padding: EdgeInsets.all(4),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              _passwordAction(
                Icons.check_rounded,
                const Color(0xFF16A34A),
                () => _savePassword(u),
              ),
              _passwordAction(
                Icons.close_rounded,
                Colors.grey,
                () => setState(() => _editingPasswordFor = null),
              ),
            ],
          ] else ...[
            Flexible(
              child: Text(
                u.password,
                style: textStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canEdit) ...[
              const SizedBox(width: 6),
              Icon(Icons.edit_rounded, size: 14, color: Colors.grey[500]),
            ],
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: canEdit && !editing
          ? GestureDetector(
              onTap: () => setState(() {
                _editingPasswordFor = u.userId;
                _passwordCtrl.text = u.password;
                _passwordCtrl.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: u.password.length,
                );
              }),
              child: MouseRegion(cursor: SystemMouseCursors.click, child: pill),
            )
          : pill,
    );
  }

  Widget _passwordAction(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  Future<void> _savePassword(UserModel u) async {
    final password = _passwordCtrl.text.trim();
    if (password == u.password) {
      setState(() => _editingPasswordFor = null);
      return;
    }
    if (password.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пароль: минимум 4 символа'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _savingPassword = true);
    // Backend filial/kategoriyalarni qayta yozadi — mavjudlarini yuboramiz.
    final success = await _userService.updateUser(
      userId: u.userId,
      username: u.username,
      role: u.role,
      password: password,
      filialIds: u.filialIds,
      categories: u.categories,
    );
    if (!mounted) return;
    setState(() => _savingPassword = false);
    if (success) {
      setState(() => _editingPasswordFor = null);
      _replaceUser(u.copyWith(password: password));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось сохранить'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _telegramLine(String username) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: () => _openTelegram(username),
        child: Row(
          children: [
            Icon(Icons.send_outlined, size: 14, color: Colors.grey[400]),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '@$username',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF3699ff),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── O'sha foydalanuvchi paroli bilan kirish (ikki marta bosilganda) ────

  /// Super admin shu foydalanuvchi nomidan kiradi (orqaga qaytish —
  /// AppBar'dagi «Супер админ» tugmasi).
  Future<void> _loginAsUser(UserModel u) => loginAsUser(context, u);

  // ── Shared widgets ─────────────────────────────────────────────────────

  static const List<String> _roles = ['super_admin', 'checker', 'worker'];

  /// Rol bejji. Super admin uchun bosilsa — shu yerning o'zida rolni
  /// almashtiradigan menyu ochiladi (tahrirlash oynasi ochilmaydi).
  /// O'z rolini o'zgartirib bo'lmaydi — kirishdan chiqib ketmaslik uchun.
  Widget _roleBadge(UserModel u) {
    final role = u.role;
    final isSuper = role == 'super_admin';
    final fg = isSuper ? const Color(0xFF92400E) : const Color(0xFF3730A3);
    final canChange =
        sl<TokenStorage>().getUserData()?.role == 'super_admin' && !_isMe(u);

    final badge = Container(
      padding: EdgeInsets.only(
        left: 8,
        right: canChange ? 4 : 8,
        top: 3,
        bottom: 3,
      ),
      decoration: BoxDecoration(
        color: isSuper ? const Color(0xFFFEF3C7) : const Color(0xFFE0E7FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _roleLabel(role),
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          if (canChange) Icon(Icons.expand_more_rounded, size: 14, color: fg),
        ],
      ),
    );
    if (!canChange) return badge;

    return PopupMenuButton<String>(
      tooltip: 'Изменить роль',
      position: PopupMenuPosition.under,
      onSelected: (r) => _changeRole(u, r),
      itemBuilder: (_) => [
        for (final r in _roles)
          PopupMenuItem<String>(
            value: r,
            height: 40,
            child: Row(
              children: [
                Icon(
                  r == role
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 18,
                  color: r == role
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 10),
                Text(
                  _roleLabel(r),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: r == role ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: badge,
    );
  }

  /// Optimistik: rol darhol o'zgaradi, server xato qaytarsa orqaga qaytadi.
  Future<void> _changeRole(UserModel u, String role) async {
    if (role == u.role) return;
    _replaceUser(u.copyWith(role: role));

    final success = await _userService.updateUser(
      userId: u.userId,
      username: u.username,
      role: role,
      filialIds: u.filialIds,
      categories: u.categories,
      canManageTasks: u.canManageTasks,
    );
    if (!mounted) return;
    if (!success) {
      _replaceUser(u);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось сохранить'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────

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
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                    errorBuilder: (_, __, ___) => Container(
                      width: 320,
                      height: 320,
                      color: Colors.grey[800],
                      alignment: Alignment.center,
                      child: const Icon(
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
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(ctx),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
            if (name.isNotEmpty)
              Positioned(
                left: 16,
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
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
