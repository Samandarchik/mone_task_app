import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/ui/add_worker.dart';
import 'package:mone_task_app/admin/ui/edit.dart';
import 'package:mone_task_app/admin/service/user_service.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
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
  List<CategoryModel> _categories = [];
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
        svc.fetchCategories(),
        svc.fetchFilials(),
      ]);
      final users = results[0] as List<UserModel>;
      users.sort((a, b) => _roleOrder(a.role).compareTo(_roleOrder(b.role)));
      if (mounted) {
        setState(() {
          _users = users;
          _categories = results[1] as List<CategoryModel>;
          _filials = results[2] as List<FilialModel>;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(title: const Text('Пользователи')),
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
                      _thFlex('Категории', 2),
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
      itemBuilder: (_, i) => _row(_users[i]),
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

  Widget _row(UserModel u) {
    final phone = u.phoneNumber ?? u.login;
    final imgUrl = u.photoUrl ?? '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _deleteUser(u.userId),
      onDoubleTap: () => _showUserInfo(u),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(width: 36, child: Text('${u.userId}', style: TextStyle(fontSize: 13, color: Colors.grey[500]))),
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
                    onTap: () => _showUserInfo(u),
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
            Expanded(flex: 2, child: _categoriesSelector(u)),
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
    final success = await _userService.updateUser(userId: u.userId, username: u.username, role: next, categories: u.categories, filialIds: u.filialIds);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Обновлено'), backgroundColor: Colors.green));
      _load();
    }
  }

  // ── Filial selector ────────────────────────────────────────────────────

  Widget _filialSelector(UserModel u) {
    if (u.role == 'super_admin') {
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
    final success = await _userService.updateUser(userId: u.userId, username: u.username, role: u.role, categories: u.categories, filialIds: selected.toList());
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Обновлено'), backgroundColor: Colors.green));
      _load();
    }
  }

  // ── Categories selector ────────────────────────────────────────────────

  Widget _categoriesSelector(UserModel u) {
    if (u.role == 'super_admin') {
      return Text('—', style: TextStyle(fontSize: 12, color: Colors.grey[600]));
    }
    final cats = u.categories ?? [];
    final btnKey = GlobalKey();
    final isEmpty = cats.isEmpty;
    return GestureDetector(
      onTap: () => _openCategoryMenu(u, btnKey),
      child: Container(
        key: btnKey,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE5E7EB))),
        child: Row(
          children: [
            if (!isEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(20)),
                child: Text('${cats.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                isEmpty ? 'Выбрать категории' : cats.join(' · '),
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

  Future<void> _openCategoryMenu(UserModel u, GlobalKey anchorKey) async {
    final selected = Set<String>.from(u.categories ?? []);
    final initial = Set<String>.from(selected);

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
              if (_categories.isEmpty) {
                return Padding(padding: const EdgeInsets.all(16), child: Text('Категорий нет', style: TextStyle(color: Colors.grey[600])));
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _categories.map((c) {
                      final sel = selected.contains(c.name);
                      return InkWell(
                        onTap: () => setS(() { sel ? selected.remove(c.name) : selected.add(c.name); }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          color: sel ? const Color(0xFFEFF6FF) : Colors.white,
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                width: 20, height: 20,
                                decoration: BoxDecoration(
                                  color: sel ? const Color(0xFF2563EB) : Colors.white,
                                  border: Border.all(color: sel ? const Color(0xFF2563EB) : const Color(0xFFD1D5DB), width: 1.6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: sel ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(c.name, style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.w500, color: sel ? const Color(0xFF1E40AF) : const Color(0xFF111827))),
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
    final success = await _userService.updateUser(userId: u.userId, username: u.username, role: u.role, categories: selected.toList(), filialIds: u.filialIds);
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
    final cats = u.categories;

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
          if (isWide) ...[
            const SizedBox(width: 14),
            _categoriesColumn(u, cats),
          ],
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
            onTap: () => _showUserInfo(u),
            onLongPress: () => _deleteUser(u.userId),
            onDoubleTap: () => _showUserInfo(u),
            child: cardContent,
          ),
          if (!isWide) _phoneCategoriesPanel(u, cats),
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

  // ── Kategoriyalar ustuni (profil, keng layout) ─────────────────────────

  Widget _categoriesColumn(UserModel u, List<String>? cats) {
    final isSuper = u.role == 'super_admin';
    final catList = cats ?? [];
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Text('Категории', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isSuper ? const Color(0xFFFEF3C7) : (catList.isEmpty ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(isSuper ? '∞' : '${catList.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isSuper ? const Color(0xFF92400E) : (catList.isEmpty ? const Color(0xFF991B1B) : const Color(0xFF166534)))),
            ),
          ]),
          const SizedBox(height: 10),
          if (isSuper)
            Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 18), alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFDE68A))),
              child: const Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.admin_panel_settings_rounded, size: 26, color: Color(0xFF92400E)),
                SizedBox(height: 6),
                Text('Видит все категории', style: TextStyle(fontSize: 12, color: Color(0xFF92400E), fontWeight: FontWeight.w600)),
              ]),
            )
          else if (catList.isEmpty)
            Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 18), alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.layers_clear_rounded, size: 26, color: Colors.grey[400]),
                const SizedBox(height: 6),
                Text('Нет категорий', style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500)),
              ]),
            )
          else
            ...catList.map((c) => Container(
              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
              child: Row(children: [
                const Icon(Icons.label_rounded, size: 14, color: Color(0xFF3699ff)),
                const SizedBox(width: 8),
                Expanded(child: Text(c, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)), overflow: TextOverflow.ellipsis)),
              ]),
            )),
        ],
      ),
    );
  }

  // ── Kategoriyalar paneli (profil, tor layout) ──────────────────────────

  Widget _phoneCategoriesPanel(UserModel u, List<String>? cats) {
    final isSuper = u.role == 'super_admin';
    final catList = cats ?? [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE5E7EB))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.visibility_rounded, size: 14, color: Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text('Категории', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey[700], letterSpacing: 0.3)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: isSuper ? const Color(0xFF92400E) : const Color(0xFF2563EB), borderRadius: BorderRadius.circular(20)),
              child: Text(isSuper ? '∞' : '${catList.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          if (isSuper)
            const Text('Видит все', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF92400E)))
          else if (catList.isEmpty)
            Text('Нет', style: TextStyle(fontSize: 12, color: Colors.grey[500]))
          else
            Wrap(
              spacing: 6, runSpacing: 6,
              children: catList.map((c) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFBFDBFE))),
                child: Text(c, style: const TextStyle(fontSize: 11, color: Color(0xFF1E40AF), fontWeight: FontWeight.w600)),
              )).toList(),
            ),
        ]),
      ),
    );
  }

  // ── User info dialog ───────────────────────────────────────────────────

  void _showUserInfo(UserModel u) {
    final phone = u.phoneNumber ?? u.login;
    final cats = u.categories;
    final pos = u.position;
    final tg = u.telegram;
    final imgUrl = u.photoUrl ?? '';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  GestureDetector(
                    onTap: imgUrl.isNotEmpty ? () { Navigator.pop(ctx); _showAvatarPreview(imgUrl, u.fullName); } : null,
                    child: Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, color: const Color(0xFFE0E7FF),
                        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                        image: imgUrl.isNotEmpty ? DecorationImage(image: NetworkImage(imgUrl), fit: BoxFit.cover, onError: (_, __) {}) : null,
                      ),
                      alignment: Alignment.center,
                      child: imgUrl.isEmpty ? Text(u.fullName.trim().isNotEmpty ? u.fullName.trim()[0].toUpperCase() : '?', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Color(0xFF3730A3))) : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(u.fullName.isNotEmpty ? u.fullName : '—', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Color(0xFF111827))),
                    const SizedBox(height: 6),
                    _roleBadge(u.role),
                  ])),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (phone.isNotEmpty) _infoRow('Телефон', phone, onTap: () => _callPhone(phone), valueColor: const Color(0xFF2563EB)),
                      _infoRow('Логин', u.login),
                      if (u.password.isNotEmpty) _infoRow('Пароль', u.password),
                      if (pos != null && pos.isNotEmpty) _infoRow('Должность', pos),
                      if (tg != null && tg.isNotEmpty) _infoRow('Telegram', '@$tg', onTap: () => _openTelegram(tg), valueColor: const Color(0xFF3699ff)),
                      if (u.filialIds != null && u.filialIds!.isNotEmpty)
                        _infoRow('Филиалы', u.filialIds!.map((id) {
                          final f = _filials.where((f) => f.filialId == id);
                          return f.isNotEmpty ? f.first.name : '#$id';
                        }).join(', ')),
                      const SizedBox(height: 8),
                      _sectionLabel('Категории'),
                      const SizedBox(height: 6),
                      if (u.role == 'super_admin')
                        Container(
                          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14), alignment: Alignment.center,
                          decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFDE68A))),
                          child: const Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.admin_panel_settings_rounded, size: 26, color: Color(0xFF92400E)),
                            SizedBox(height: 6),
                            Text('Видит все категории', style: TextStyle(fontSize: 12, color: Color(0xFF92400E), fontWeight: FontWeight.w600)),
                          ]),
                        )
                      else if (cats == null || cats.isEmpty)
                        Text('—', style: TextStyle(fontSize: 13, color: Colors.grey[600]))
                      else
                        Wrap(
                          spacing: 6, runSpacing: 6,
                          children: cats.map((c) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(20)),
                            child: Text(c, style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
                          )).toList(),
                        ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(context, MaterialPageRoute(builder: (_) => EditUserPage(user: u, category: widget.filialModel))).then((result) { if (result == true) _load(); });
                          },
                          icon: const Icon(Icons.edit_rounded, size: 16),
                          label: const Text('Редактировать'),
                        )),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () { Navigator.pop(ctx); _deleteUser(u.userId); },
                          icon: const Icon(Icons.delete_rounded, size: 16, color: Colors.red),
                          label: const Text('Удалить', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey[600], letterSpacing: 0.4));

  Widget _infoRow(String label, String value, {VoidCallback? onTap, Color? valueColor}) {
    final text = Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: valueColor ?? const Color(0xFF111827), decoration: onTap != null ? TextDecoration.underline : null, decorationColor: valueColor));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600]))),
        Expanded(child: onTap != null ? GestureDetector(onTap: onTap, child: text) : text),
      ]),
    );
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
