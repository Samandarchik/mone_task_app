import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/user_service.dart';
import 'package:mone_task_app/worker/model/user_model.dart';

/// Foydalanuvchini bitta tap bilan tahrirlash dialogi:
/// ism, telefon, parol, rol va "Заменить резюме" (rezumeni HR'dan yangilash).
class UserEditDialog extends StatefulWidget {
  final UserModel user;
  final List<FilialModel> filials;

  const UserEditDialog({super.key, required this.user, required this.filials});

  /// Saqlangan bo'lsa `true` qaytaradi.
  static Future<bool?> show(
    BuildContext context, {
    required UserModel user,
    required List<FilialModel> filials,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => UserEditDialog(user: user, filials: filials),
    );
  }

  @override
  State<UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<UserEditDialog> {
  static const String _rezumeBaseUrl = 'https://hr.monebakeryuz.uz';

  // Bu ilovaning rollari
  static const List<({String value, String label})> _roles = [
    (value: 'super_admin', label: 'Супер админ'),
    (value: 'checker', label: 'Корректор'),
    (value: 'worker', label: 'Ревизор'),
  ];

  final UserService _userService = UserService();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _passwordController;
  late String _selectedRole;
  late List<int> _selectedFilialIds;

  Map<String, dynamic>? _rezume;
  bool _replacingRezume = false;
  String? _rezumeMessage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.username);
    _phoneController = TextEditingController(
      text: widget.user.phoneNumber ?? widget.user.login,
    );
    _passwordController = TextEditingController(text: widget.user.password);
    _selectedRole = widget.user.role;
    _selectedFilialIds = List<int>.from(widget.user.filialIds ?? const []);
    _rezume = widget.user.profile;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Rezumeni almashtirish (HR'dan qayta yuklash) ────────────────────────

  Future<void> _replaceRezume() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _rezumeMessage = 'Введите телефон');
      return;
    }

    setState(() {
      _replacingRezume = true;
      _rezumeMessage = null;
    });

    try {
      final normalized = phone.startsWith('+') || phone.startsWith('998')
          ? phone
          : '998$phone';
      final url = '$_rezumeBaseUrl/api/public/rezume-by-phone/$normalized';
      final resp = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ),
      ).get(url, options: Options(validateStatus: (_) => true));

      if (resp.statusCode != 200) {
        setState(() {
          _rezumeMessage = 'Резюме не найдено (${resp.statusCode})';
          _replacingRezume = false;
        });
        return;
      }

      final data = (resp.data is String
          ? jsonDecode(resp.data as String)
          : resp.data) as Map<String, dynamic>;
      data.remove('interviews');

      final familiya = (data['familiya'] ?? '').toString().trim();
      final ism = (data['ism'] ?? '').toString().trim();
      final sharif = (data['sharif'] ?? '').toString().trim();
      final fio = [familiya, ism, sharif].where((s) => s.isNotEmpty).join(' ');
      if (fio.isNotEmpty) _nameController.text = fio;

      setState(() {
        _rezume = data;
        _rezumeMessage = 'Резюме заменено ✓';
        _replacingRezume = false;
      });
    } catch (e) {
      setState(() {
        _rezumeMessage = 'Ошибка: $e';
        _replacingRezume = false;
      });
    }
  }

  // ── Saqlash ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Имя не указано');
      return;
    }
    final password = _passwordController.text.trim();
    if (password.isNotEmpty && password.length < 4) {
      _showError('Пароль: минимум 4 символа');
      return;
    }

    setState(() => _saving = true);

    final phone = _phoneController.text.trim();
    final changedPassword =
        password.isNotEmpty && password != widget.user.password
            ? password
            : null;

    final success = await _userService.updateUser(
      userId: widget.user.userId,
      username: name,
      role: _selectedRole,
      password: changedPassword,
      filialIds: _selectedFilialIds.isNotEmpty ? _selectedFilialIds : null,
      phoneNumber: phone.isNotEmpty ? phone : null,
      profileJson: _rezume != null ? jsonEncode(_rezume) : null,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      Navigator.pop(context, true);
    } else {
      _showError('Произошла ошибка');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.edit, color: Color(0xFF3699ff)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.user.fullName.isNotEmpty
                        ? widget.user.fullName.toUpperCase()
                        : widget.user.username.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(
                        controller: _nameController,
                        label: 'Имя',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _phoneController,
                        label: 'Телефон',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _passwordController,
                        label: 'Пароль',
                        icon: Icons.vpn_key_outlined,
                      ),
                      const SizedBox(height: 16),
                      const Text('Роль',
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFF6B7280))),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _roles.map((r) {
                          final selected = _selectedRole == r.value;
                          return ChoiceChip(
                            label: Text(r.label),
                            selected: selected,
                            onSelected: (_) =>
                                setState(() => _selectedRole = r.value),
                          );
                        }).toList(),
                      ),
                      if (_selectedRole == 'worker') ...[
                        const SizedBox(height: 16),
                        const Text('Филиалы',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF6B7280))),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.filials.map((f) {
                            final selected =
                                _selectedFilialIds.contains(f.filialId);
                            return FilterChip(
                              label: Text(f.name),
                              selected: selected,
                              onSelected: (v) => setState(() {
                                if (v) {
                                  _selectedFilialIds.add(f.filialId);
                                } else {
                                  _selectedFilialIds.remove(f.filialId);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _replacingRezume ? null : _replaceRezume,
                          icon: _replacingRezume
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.swap_horiz, size: 18),
                          label: const Text('Заменить резюме'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      if (_rezumeMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _rezumeMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: _rezumeMessage!.contains('✓')
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, false),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Сохранить'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFFF3F4F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
