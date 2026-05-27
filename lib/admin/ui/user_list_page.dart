import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/ui/add_worker.dart';
import 'package:mone_task_app/admin/ui/dialog.dart';
import 'package:mone_task_app/admin/ui/edit.dart';
import 'package:mone_task_app/admin/service/user_service.dart';
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
  final UserService _userService = UserService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await _userService.fetchUsers();
      users.sort((a, b) => _roleOrder(a.role).compareTo(_roleOrder(b.role)));
      if (mounted) setState(() { _users = users; _loading = false; });
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
    final confirm = await NativeDialog.showDeleteDialog();
    if (!confirm) return;
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
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      '${_users.length} пользователей',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AddWorkerPage()),
                        );
                        if (result == true) _load();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Новый пользователь'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Table header
              Container(
                color: const Color(0xFFF9FAFB),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    _th('#', 36),
                    const SizedBox(width: 60),
                    _thFlex('Имя', 2),
                    _th('Роль', 150),
                    _thFlex('Категории', 2),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Table body
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _users.isEmpty
                        ? const Center(child: Text('Пользователи не найдены'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              itemCount: _users.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) => _row(_users[i]),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _th(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey[600], letterSpacing: 0.5),
      ),
    );
  }

  Widget _thFlex(String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey[600], letterSpacing: 0.5),
      ),
    );
  }

  Widget _row(UserModel u) {
    final photoUrl = u.photoUrl;
    final phone = u.phoneNumber ?? u.login;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _deleteUser(u.userId),
      onDoubleTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EditUserPage(user: u, category: widget.filialModel)),
        );
        if (result == true) _load();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // #
            SizedBox(
              width: 36,
              child: Text('${u.userId}', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            ),

            // Avatar
            SizedBox(
              width: 60,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE0E7FF),
                  border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                  image: photoUrl != null
                      ? DecorationImage(
                          image: NetworkImage(photoUrl),
                          fit: BoxFit.cover,
                          onError: (_, __) {},
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: photoUrl == null
                    ? Text(
                        u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF3730A3)),
                      )
                    : null,
              ),
            ),

            // Name + phone
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    u.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF111827)),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _callPhone(phone),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone_rounded, size: 13, color: Color(0xFF2563EB)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              phone,
                              style: const TextStyle(
                                fontSize: 13,
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
                ],
              ),
            ),

            // Role badge
            SizedBox(
              width: 150,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _roleBadge(u.role),
              ),
            ),

            // Categories
            Expanded(
              flex: 2,
              child: _categoriesCell(u),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleBadge(String role) {
    final isSuper = role == 'super_admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: isSuper ? const Color(0xFFFEF3C7) : const Color(0xFFE0E7FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSuper ? const Color(0xFFFDE68A) : const Color(0xFFC7D2FE),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isSuper) ...[
            Container(
              width: 7, height: 7,
              decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            _roleLabel(role),
            style: TextStyle(
              color: isSuper ? const Color(0xFF92400E) : const Color(0xFF3730A3),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoriesCell(UserModel u) {
    final cats = u.categories;
    if (u.role == 'super_admin') {
      return const Text('—', style: TextStyle(color: Colors.grey));
    }
    if (cats == null || cats.isEmpty) {
      return Text('Нет категорий', style: TextStyle(fontSize: 13, color: Colors.grey[400]));
    }

    final text = cats.join(' / ');
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${cats.length}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF166534)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}
