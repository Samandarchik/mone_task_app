import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/service/user_service.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/shared/widgets/switch_chip.dart';
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
  late final List<int> _selectedFilialIds;
  late List<String> _selectedCategories;

  List<CategoryModel> _categories = [];

  Map<String, dynamic>? _rezume;
  bool _replacingRezume = false;
  String? _rezumeMessage;
  bool _saving = false;

  bool get _isMe =>
      sl<TokenStorage>().getUserData()?.userId == widget.user.userId;

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
    _selectedCategories = List<String>.from(widget.user.categories ?? const []);
    _rezume = widget.user.profile;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await TemplateService().fetchCategoriesList();
      if (mounted) setState(() => _categories = categories);
    } catch (_) {}
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

      final data =
          (resp.data is String ? jsonDecode(resp.data as String) : resp.data)
              as Map<String, dynamic>;
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
      categories: _selectedCategories.isNotEmpty ? _selectedCategories : null,
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
              _buildHeader(),
              const SizedBox(height: 20),
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
                      _buildPasswordField(),
                      const SizedBox(height: 20),
                      // O'zining rolini o'zgartira olmaydi (super admin
                      // huquqini yo'qotib qo'ymaslik uchun).
                      if (!_isMe) ...[
                        _sectionTitle('Роль'),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<String>(
                            segments: _roles
                                .map(
                                  (r) => ButtonSegment(
                                    value: r.value,
                                    label: Text(r.label),
                                  ),
                                )
                                .toList(),
                            selected: {_selectedRole},
                            onSelectionChanged: _saving
                                ? null
                                : (s) =>
                                      setState(() => _selectedRole = s.first),
                          ),
                        ),
                      ],
                      if (_selectedRole == 'worker') ...[
                        const SizedBox(height: 20),
                        _sectionTitle('Категории'),
                        const SizedBox(height: 10),
                        SwitchChipGrid(
                          children: _categories.map((c) {
                            final selected = _selectedCategories.contains(
                              c.name,
                            );
                            return SwitchChip(
                              label: c.name,
                              value: selected,
                              onChanged: (v) => setState(() {
                                if (v) {
                                  _selectedCategories.add(c.name);
                                } else {
                                  _selectedCategories.remove(c.name);
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
                                    strokeWidth: 2,
                                  ),
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
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
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
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
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

  static const _roleLabels = {
    'super_admin': 'Супер админ',
    'checker': 'Корректор',
    'worker': 'Ревизор',
  };

  Widget _buildHeader() {
    final name = widget.user.fullName.isNotEmpty
        ? widget.user.fullName
        : widget.user.username;
    final photo = widget.user.photoUrl ?? '';
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFFE0E7FF),
          backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
          child: photo.isEmpty
              ? Text(
                  name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3730A3),
                  ),
                )
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _roleLabels[widget.user.role] ?? widget.user.role,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          icon: const Icon(Icons.close_rounded, color: Color(0xFF9CA3AF)),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Color(0xFF374151),
      ),
    );
  }

  /// Parol — katta va aniq ko'rinadi, nusxa olish tugmasi bilan
  Widget _buildPasswordField() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E7FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.key_rounded,
              size: 20,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Пароль',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                TextField(
                  controller: _passwordController,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: Color(0xFF111827),
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.only(top: 2),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Копировать',
            icon: const Icon(
              Icons.copy_rounded,
              size: 20,
              color: Color(0xFF6B7280),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _passwordController.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Пароль скопирован')),
              );
            },
          ),
        ],
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
