import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/ui/add_worker.dart';
import 'package:mone_task_app/admin/ui/user_edit_dialog.dart';
import 'package:mone_task_app/admin/service/user_service.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/model/login_model.dart';
import 'package:mone_task_app/home/service/api_service.dart';
import 'package:mone_task_app/home/ui/role_home.dart';
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
  final UserService _userService = UserService();
  bool _profileView = false;

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
      if (mounted) setState(() => _loading = false);
    }
  }

  int _roleOrder(String role) {
    switch (role) {
      case 'super_admin': return 0;
      case 'checker': return 1;
      case 'worker': return 2;
      default: return 3;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'super_admin': return 'Супер админ';
      case 'checker': return 'Корректор';
      case 'worker': return 'Ревизор';
      default: return role;
    }
  }

  Future<void> _deleteUser(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить'),
        content: const Text('Вы уверены, что хотите удалить этого пользователя?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
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
    if (success) {
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пользователь удалён'), backgroundColor: Colors.green),
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
    messenger.showSnackBar(
      const SnackBar(content: Text('Отправляется...')),
    );
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
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      '${_users.length} пользователей',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                    ),
                    const Spacer(),
                    _viewToggleButton(),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AddWorkerPage()),
                        );
                        if (result == true) _load();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Новый'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (!_profileView) ...[
                Container(
                  color: const Color(0xFFF9FAFB),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  Widget _toggleSeg({required IconData icon, required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? const Color(0xFF2563EB) : const Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? const Color(0xFF111827) : const Color(0xFF6B7280),
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
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey[600], letterSpacing: 0.5)),
    );
  }

  Widget _thFlex(String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey[600], letterSpacing: 0.5)),
    );
  }

  Widget _row(UserModel u, int index) {
    final phone = u.phoneNumber ?? u.login;
    final imgUrl = u.photoUrl ?? '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showEditDialog(u),
      onLongPress: () => _deleteUser(u.userId),
      onDoubleTap: () => _loginAsUser(u),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(width: 36, child: Text('$index', style: TextStyle(fontSize: 13, color: Colors.grey[500]))),
            SizedBox(
              width: 60,
              child: GestureDetector(
                onTap: imgUrl.isNotEmpty ? () => _showAvatarPreview(imgUrl, u.fullName) : null,
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE0E7FF),
                    border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                    image: imgUrl.isNotEmpty
                        ? DecorationImage(image: NetworkImage(imgUrl), fit: BoxFit.cover, onError: (_, __) {})
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: imgUrl.isEmpty
                      ? Text(
                          u.fullName.trim().isNotEmpty ? u.fullName.trim()[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF3730A3)),
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
                  GestureDetector(
                    onTap: () => _showEditDialog(u),
                    child: Text(
                      u.fullName.isNotEmpty ? u.fullName : '—',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF111827)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _callPhone(phone),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone_rounded, size: 14, color: Color(0xFF2563EB)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              phone,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF2563EB), decoration: TextDecoration.underline, decorationColor: Color(0xFF2563EB)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (u.password.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.key_rounded, size: 14, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(u.password, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF6B7280)), overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: _roleSelector(u))),
            Expanded(flex: 2, child: _filialSelector(u)),
            // Bitta foydalanuvchiga login ma'lumotlarini Telegram orqali yuborish.
            if (u.role != 'super_admin' &&
                sl<TokenStorage>().getUserData()?.role == 'super_admin')
              IconButton(
                tooltip: 'Отправить в Telegram',
                icon: const Icon(Icons.send_rounded, size: 20, color: Color(0xFF2563EB)),
                onPressed: () => _sendCredentials(u),
              ),
          ],
        ),
      ),
    );
  }

  // ── Role selector ──────────────────────────────────────────────────────

  Widget _roleSelector(UserModel u) {
    if (u.role == 'super_admin') return _roleBadge(u.role);
    return PopupMenuButton<String>(
      tooltip: 'Роль',
      position: PopupMenuPosition.under,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      onSelected: (next) => _changeRole(u, next),
      itemBuilder: (_) => [
        _roleMenuItem('checker', u.role == 'checker'),
        _roleMenuItem('worker', u.role == 'worker'),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFC7D2FE), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF4F46E5), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(_roleLabel(u.role), style: const TextStyle(color: Color(0xFF3730A3), fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
              alignment: Alignment.center,
              child: const Icon(Icons.expand_more_rounded, size: 16, color: Color(0xFF4F46E5)),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _roleMenuItem(String value, bool selected) {
    return PopupMenuItem<String>(
      value: value,
      padding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: selected ? const Color(0xFFEFF6FF) : Colors.white,
        child: Row(
          children: [
            Expanded(
              child: Text(
                _roleLabel(value),
                style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? const Color(0xFF1E40AF) : const Color(0xFF111827)),
              ),
            ),
            if (selected) const Icon(Icons.check_rounded, size: 16, color: Color(0xFF2563EB)),
          ],
        ),
      ),
    );
  }

  Future<void> _changeRole(UserModel u, String next) async {
    if (next == u.role) return;
    final success = await _userService.updateUser(userId: u.userId, username: u.username, role: next, filialIds: u.filialIds);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Обновлено'), backgroundColor: Colors.green));
      _load();
    }
  }

  // ── Filial selector ────────────────────────────────────────────────────

  Widget _filialSelector(UserModel u) {
    // super_admin va checker (Корректор) barcha filiallarni ko'radi —
    // filial tanlash kerak emas.
    if (u.role == 'super_admin' || u.role == 'checker') {
      return Text('—', style: TextStyle(fontSize: 12, color: Colors.grey[600]));
    }
    final ids = u.filialIds ?? [];
    final btnKey = GlobalKey();
    final isEmpty = ids.isEmpty;
    final names = ids.map((id) {
      final f = _filials.where((f) => f.filialId == id);
      return f.isNotEmpty ? f.first.name : '#$id';
    }).toList();
    return GestureDetector(
      onTap: () => _openFilialMenu(u, btnKey),
      child: Container(
        key: btnKey,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            if (!isEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF059669), borderRadius: BorderRadius.circular(20)),
                child: Text('${ids.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                isEmpty ? 'Выбрать филиалы' : names.join(' · '),
                style: TextStyle(fontSize: 12, color: isEmpty ? Colors.grey[500] : const Color(0xFF374151), fontWeight: isEmpty ? FontWeight.w500 : FontWeight.w600),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.unfold_more_rounded, size: 14, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFilialMenu(UserModel u, GlobalKey anchorKey) async {
    final selected = Set<int>.from(u.filialIds ?? []);
    final initial = Set<int>.from(selected);

    final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset(0, box.size.height + 4), ancestor: overlay);
    final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
    final position = RelativeRect.fromLTRB(topLeft.dx, topLeft.dy, overlay.size.width - bottomRight.dx, 0);

    await showMenu<void>(
      context: context,
      position: position,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 360, maxHeight: 420),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE5E7EB))),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: StatefulBuilder(
            builder: (ctx, setS) {
              if (_filials.isEmpty) {
                return Padding(padding: const EdgeInsets.all(16), child: Text('Филиалов нет', style: TextStyle(color: Colors.grey[600])));
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _filials.map((f) {
                      final sel = selected.contains(f.filialId);
                      return InkWell(
                        onTap: () => setS(() { sel ? selected.remove(f.filialId) : selected.add(f.filialId); }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          color: sel ? const Color(0xFFECFDF5) : Colors.white,
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                width: 20, height: 20,
                                decoration: BoxDecoration(
                                  color: sel ? const Color(0xFF059669) : Colors.white,
                                  border: Border.all(color: sel ? const Color(0xFF059669) : const Color(0xFFD1D5DB), width: 1.6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: sel ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(f.name, style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.w500, color: sel ? const Color(0xFF065F46) : const Color(0xFF111827))),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );

    if (selected.length == initial.length && selected.containsAll(initial)) return;
    final success = await _userService.updateUser(userId: u.userId, username: u.username, role: u.role, filialIds: selected.toList());
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Обновлено'), backgroundColor: Colors.green));
      _load();
    }
  }

  // ── Profile grid view ──────────────────────────────────────────────────

  Widget _profileGrid() {
    if (_users.isEmpty) {
      return Center(child: Text('Пользователей нет', style: TextStyle(color: Colors.grey[600])));
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _showEditDialog(u),
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
          child: Image.network(imgRaw, width: w, height: h, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(width: w, height: h, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)), child: Icon(Icons.person, size: 40, color: Colors.grey[400])),
          ),
        ),
      );
    }
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(color: const Color(0xFFE0E7FF), borderRadius: BorderRadius.circular(10)),
      alignment: Alignment.center,
      child: Text(u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '?', style: TextStyle(fontSize: w * 0.3, fontWeight: FontWeight.w700, color: const Color(0xFF3730A3))),
    );
  }

  List<Widget> _userShortFields(UserModel u) {
    final phone = u.phoneNumber ?? u.login;
    final tg = u.telegram;
    return [
      _userCardHeader(u),
      _phoneLine(phone),
      if (u.password.isNotEmpty) _passwordLine(u.password),
      if (tg != null && tg.isNotEmpty) _telegramLine(tg),
      if (u.filialIds != null && u.filialIds!.isNotEmpty)
        _profileInfoLine(Icons.location_on_outlined, u.filialIds!.map((id) {
          final f = _filials.where((f) => f.filialId == id);
          return f.isNotEmpty ? f.first.name : '#$id';
        }).join(', ')),
    ];
  }

  List<Widget> _userFullFields(UserModel u) {
    final phone = u.phoneNumber ?? u.login;
    final pos = u.position;
    final tg = u.telegram;
    return [
      _userCardHeader(u),
      if (pos != null && pos.isNotEmpty) _profileInfoLine(Icons.work_outlined, pos),
      _phoneLine(phone),
      if (u.password.isNotEmpty) _passwordLine(u.password),
      if (tg != null && tg.isNotEmpty) _telegramLine(tg),
      if (u.filialIds != null && u.filialIds!.isNotEmpty)
        _profileInfoLine(Icons.location_on_outlined, u.filialIds!.map((id) {
          final f = _filials.where((f) => f.filialId == id);
          return f.isNotEmpty ? f.first.name : '#$id';
        }).join(', ')),
    ];
  }

  Widget _userCardHeader(UserModel u) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Flexible(child: Text(u.fullName.isNotEmpty ? u.fullName : '—', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1F2937)))),
            const SizedBox(width: 8),
            _roleBadge(u.role),
          ]),
          if (u.position != null && u.position!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(u.position!, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ],
        ],
      ),
    );
  }

  Widget _profileInfoLine(IconData icon, String text, {int? maxLines}) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 14, color: Colors.grey[400])),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[700]), maxLines: maxLines, overflow: maxLines != null ? TextOverflow.ellipsis : TextOverflow.clip)),
      ]),
    );
  }

  Widget _phoneLine(String telefon) {
    if (telefon.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: () => _callPhone(telefon),
        child: Row(children: [
          Icon(Icons.phone_outlined, size: 14, color: Colors.grey[400]),
          const SizedBox(width: 8),
          Text(telefon, style: const TextStyle(fontSize: 13, color: Color(0xFF3699ff), fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _passwordLine(String password) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        const Icon(Icons.key_rounded, size: 14, color: Color(0xFF9CA3AF)),
        const SizedBox(width: 8),
        Flexible(child: Text(password, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF6B7280)), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  Widget _telegramLine(String username) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: () => _openTelegram(username),
        child: Row(children: [
          Icon(Icons.send_outlined, size: 14, color: Colors.grey[400]),
          const SizedBox(width: 8),
          Flexible(child: Text('@$username', style: const TextStyle(fontSize: 13, color: Color(0xFF3699ff), fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }

  // ── Tahrirlash dialogi (bitta tap) ─────────────────────────────────────

  Future<void> _showEditDialog(UserModel u) async {
    final saved = await UserEditDialog.show(
      context,
      user: u,
      filials: _filials,
    );
    if (saved == true) _load();
  }

  // ── O'sha foydalanuvchi paroli bilan kirish (ikki marta bosilganda) ────

  Future<void> _loginAsUser(UserModel u) async {
    if (u.password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('У пользователя нет пароля')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final result =
        await ApiService().login(LoginModel(password: u.password));
    if (!mounted) return;

    if (result['success'] == true && result['token'] != null) {
      final ts = sl<TokenStorage>();
      await ts.putToken(result['token']);
      await ts.putUserData(Map<String, dynamic>.from(result['user'] as Map));
      if (!mounted) return;
      context.pushAndRemove(
        landingForUser(UserModel.fromJson(
          Map<String, dynamic>.from(result['user'] as Map),
        )),
      );
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(
            result['message']?.toString() ?? result['error']?.toString() ?? 'Не удалось войти'),
      ));
    }
  }

  // ── Shared widgets ─────────────────────────────────────────────────────

  Widget _roleBadge(String role) {
    final isSuper = role == 'super_admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: isSuper ? const Color(0xFFFEF3C7) : const Color(0xFFE0E7FF), borderRadius: BorderRadius.circular(20)),
      child: Text(_roleLabel(role), style: TextStyle(color: isSuper ? const Color(0xFF92400E) : const Color(0xFF3730A3), fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  Future<void> _openTelegram(String username) async {
    final appUri = Uri.parse('tg://resolve?domain=$username');
    final webUri = Uri.parse('https://t.me/$username');
    try {
      if (await canLaunchUrl(appUri)) {
        final ok = await launchUrl(appUri, mode: LaunchMode.externalApplication);
        if (ok) return;
      }
    } catch (_) {}
    try { await launchUrl(webUri, mode: LaunchMode.externalApplication); } catch (_) {}
  }

  void _showAvatarPreview(String url, String name) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(children: [
          Center(child: InteractiveViewer(
            maxScale: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(url, fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
                errorBuilder: (_, __, ___) => Container(width: 320, height: 320, color: Colors.grey[800], alignment: Alignment.center, child: const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64)),
              ),
            ),
          )),
          Positioned(top: 12, right: 12, child: Material(
            color: Colors.black54, shape: const CircleBorder(),
            child: InkWell(customBorder: const CircleBorder(), onTap: () => Navigator.pop(ctx), child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.close_rounded, color: Colors.white, size: 24))),
          )),
          if (name.isNotEmpty)
            Positioned(left: 16, bottom: 16, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            )),
        ]),
      ),
    );
  }
}
