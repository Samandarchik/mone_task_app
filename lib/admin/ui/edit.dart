import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/user_service.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:mone_task_app/worker/service/log_out.dart';

class EditUserPage extends StatefulWidget {
  final List<FilialModel> category;
  final UserModel user;

  const EditUserPage({super.key, required this.user, required this.category});

  @override
  State<EditUserPage> createState() => _EditUserPageState();
}

class _EditUserPageState extends State<EditUserPage> {
  static const String _rezumeBaseUrl = 'https://hr.monebakeryuz.uz';

  late TextEditingController _usernameController;
  late TextEditingController _phoneController;
  late TextEditingController _passwordController;
  late String _selectedRole;
  late List<int> _selectedFilialIds;

  final UserService _userService = UserService();
  late Future<List<FilialModel>> _filialsFuture;
  bool _isLoading = false;
  bool _obscurePassword = true;

  // Rezume state
  bool _fetchingRezume = false;
  String? _rezumeError;
  Map<String, dynamic>? _rezume;
  String _lastSearchedDigits = '';

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user.username);
    _phoneController = TextEditingController(
      text: widget.user.phoneNumber ?? '',
    );
    _passwordController = TextEditingController(text: widget.user.password);
    _selectedRole = widget.user.role;
    _selectedFilialIds = widget.user.filialIds ?? [];
    _filialsFuture = TaskViewService().fetchFilials();
    // Mavjud rezume bo'lsa darhol ko'rsatamiz
    _rezume = widget.user.profile;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Rezume qidirish / yangilash ─────────────────────────────────────────

  void _onPhoneChanged(String value) {
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length != 12) {
      _lastSearchedDigits = '';
      if (_rezumeError != null) {
        setState(() => _rezumeError = null);
      }
      return;
    }
    if (_fetchingRezume || digits == _lastSearchedDigits) return;
    _lastSearchedDigits = digits;
    _fetchRezume();
  }

  Future<void> _fetchRezume() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;

    setState(() {
      _fetchingRezume = true;
      _rezumeError = null;
    });

    try {
      final normalized =
          phone.startsWith('+') || phone.startsWith('998') ? phone : '998$phone';
      final url = '$_rezumeBaseUrl/api/public/rezume-by-phone/$normalized';
      final resp = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ),
      ).get(url, options: Options(validateStatus: (_) => true));

      if (resp.statusCode != 200) {
        setState(() {
          _rezumeError = 'Резюме не найдено (${resp.statusCode})';
          _fetchingRezume = false;
        });
        return;
      }

      final data = (resp.data is String
          ? jsonDecode(resp.data as String)
          : resp.data) as Map<String, dynamic>;
      data.remove('interviews');

      // Avtomatik to'ldirish (ism bo'sh bo'lsa)
      final familiya = (data['familiya'] ?? '').toString().trim();
      final ism = (data['ism'] ?? '').toString().trim();
      final sharif = (data['sharif'] ?? '').toString().trim();
      final fio = [familiya, ism, sharif].where((s) => s.isNotEmpty).join(' ');
      if (fio.isNotEmpty && _usernameController.text.trim().isEmpty) {
        _usernameController.text = fio;
      }

      setState(() {
        _rezume = data;
        _fetchingRezume = false;
      });
    } catch (e) {
      setState(() {
        _rezumeError = 'Ошибка: $e';
        _fetchingRezume = false;
      });
    }
  }

  // ── Saqlash ─────────────────────────────────────────────────────────────

  Future<void> _saveUser() async {
    if (_usernameController.text.trim().isEmpty) {
      _showError('Имя не указано');
      return;
    }
    if (_selectedRole == 'worker' && _selectedFilialIds.isEmpty) {
      _showError('Филиал не выбран');
      return;
    }
    final password = _passwordController.text.trim();
    if (password.isNotEmpty && password.length < 6) {
      _showError('Код: минимум 6 символов');
      return;
    }

    setState(() => _isLoading = true);

    final phone = _phoneController.text.trim();
    // Kod o'zgartirilgan bo'lsagina yuboramiz
    final changedPassword =
        password.isNotEmpty && password != widget.user.password ? password : null;
    final success = await _userService.updateUser(
      userId: widget.user.userId,
      username: _usernameController.text.trim(),
      role: _selectedRole,
      password: changedPassword,
      filialIds: _selectedFilialIds.isNotEmpty ? _selectedFilialIds : null,
      phoneNumber: phone.isNotEmpty ? phone : null,
      profileJson: _rezume != null ? jsonEncode(_rezume) : null,
    );

    setState(() => _isLoading = false);

    if (success && mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено')),
      );
    } else if (mounted) {
      _showError('Произошла ошибка');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать'),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(onPressed: _saveUser, icon: const Icon(Icons.check)),
        ],
      ),
      body: FutureBuilder<List<FilialModel>>(
        future: _filialsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Данные не загружены'));
          }

          final filials = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Telefon — rezumeni yangilash uchun
                _buildPhoneField(),
                const SizedBox(height: 16),

                if (_rezumeError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_rezumeError!,
                        style: TextStyle(color: Colors.red.shade900)),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_rezume != null) ...[
                  _buildRezumePreview(_rezume!),
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Kod / parol — foydalanuvchi shu bilan tizimga kiradi
                _buildPasswordField(),
                const SizedBox(height: 16),

                if (_selectedRole == 'worker') ...[
                  _buildSectionTitle('Филиал'),
                  const SizedBox(height: 8),
                  ...filials.map((filial) => _buildSwitchRow(
                        title: filial.name,
                        value: _selectedFilialIds.contains(filial.filialId),
                        onChanged: (value) {
                          setState(() {
                            if (value) {
                              _selectedFilialIds.add(filial.filialId);
                            } else {
                              _selectedFilialIds.remove(filial.filialId);
                            }
                          });
                        },
                      )),
                  const SizedBox(height: 16),
                ],

                ElevatedButton(
                  onPressed: () async {
                    await LogOutService().logOutUser(widget.user.userId);
                  },
                  child: const Text("Выйти из аккаунта"),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Telefon maydoni ─────────────────────────────────────────────────────

  Widget _buildPhoneField() {
    return TextField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
      ],
      decoration: InputDecoration(
        labelText: 'Телефон (обновить резюме)',
        hintText: '998901234567',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.phone),
        suffixIcon: _fetchingRezume
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _fetchRezume,
                tooltip: 'Обновить резюме',
              ),
      ),
      onChanged: _onPhoneChanged,
      onSubmitted: (_) => _fetchRezume(),
    );
  }

  // ── Rezume preview ──────────────────────────────────────────────────────

  Widget _buildRezumePreview(Map<String, dynamic> r) {
    final familiya = (r['familiya'] ?? '').toString();
    final ism = (r['ism'] ?? '').toString();
    final sharif = (r['sharif'] ?? '').toString();
    final fio = [familiya, ism, sharif].where((s) => s.isNotEmpty).join(' ');
    final rasm = (r['rasm_url'] ?? '').toString();
    final photoUrl = rasm.isEmpty
        ? null
        : (rasm.startsWith('http') ? rasm : '$_rezumeBaseUrl$rasm');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    photoUrl,
                    width: 80,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 80,
                      height: 100,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.person, size: 40),
                    ),
                  ),
                ),
              if (photoUrl != null) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fio.isEmpty ? '(имя не найдено)' : fio,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if ((r['lavozim'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(r['lavozim'].toString(),
                          style: const TextStyle(color: Colors.grey)),
                    ],
                    const SizedBox(height: 4),
                    Text((r['telefon'] ?? '').toString()),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _kv('Дата рождения', r['tugilgan_sana']),
          _kv('Рост / Вес', '${r['boy_sm'] ?? '?'} см / ${r['vazn_kg'] ?? '?'} кг'),
          _kv('Адрес', r['yashash_manzili']),
          _kv('Ориентир', r['moljal']),
          _kv('Общий стаж', r['umumiy_tajriba']),
          _kv('Зарубежный опыт', r['chet_el_tajribasi']),
          _kv('Образование', r['malumot']),
          _kv('Семейное положение', r['oilaviy_holat']),
          if (r['tillar'] is List)
            _kv(
                'Языки',
                (r['tillar'] as List)
                    .map((t) => '${(t as Map)['til']}: ${t['daraja']}')
                    .join(', ')),
          if ((r['qoshimcha'] ?? '').toString().isNotEmpty)
            _kv('Дополнительно', r['qoshimcha']),
          if ((r['tg_username'] ?? '').toString().isNotEmpty)
            _kv('Telegram', '@${r['tg_username']}'),
        ],
      ),
    );
  }

  Widget _kv(String label, dynamic value) {
    final v = (value ?? '').toString();
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: 'Код входа',
        hintText: 'Код для входа в приложение',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.key),
        suffixIcon: IconButton(
          icon: Icon(
              _obscurePassword ? Icons.visibility_off : Icons.visibility),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Center(
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(title, style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
        CupertinoSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}
