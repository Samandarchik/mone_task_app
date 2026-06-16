import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/user_service.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';

class AddWorkerPage extends StatefulWidget {
  const AddWorkerPage({super.key});

  @override
  State<AddWorkerPage> createState() => _AddWorkerPageState();
}

class _AddWorkerPageState extends State<AddWorkerPage> {
  static const String _rezumeBaseUrl = 'https://hr.monebakeryuz.uz';

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  final String _selectedRole = 'worker';
  final List<int> _selectedFilialIds = [];
  bool _isLoading = false;
  bool _obscurePassword = true;

  // Rezume state
  bool _fetchingRezume = false;
  String? _rezumeError;
  Map<String, dynamic>? _rezume;
  String _lastSearchedDigits = '';

  final UserService _userService = UserService();
  List<FilialModel>? _filials;
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final filials = await TaskViewService().fetchFilials();
      setState(() {
        _filials = filials;
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ── Rezume qidirish ─────────────────────────────────────────────────────

  void _onPhoneChanged(String value) {
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length != 12) {
      if (digits != _lastSearchedDigits && (_rezume != null || _rezumeError != null)) {
        setState(() {
          _rezume = null;
          _rezumeError = null;
        });
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
      _rezume = null;
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

      // Avtomatik to'ldirish
      final familiya = (data['familiya'] ?? '').toString().trim();
      final ism = (data['ism'] ?? '').toString().trim();
      final sharif = (data['sharif'] ?? '').toString().trim();
      final fio = [familiya, ism, sharif].where((s) => s.isNotEmpty).join(' ');
      if (fio.isNotEmpty && _usernameController.text.isEmpty) {
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
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRole == 'worker' && _selectedFilialIds.isEmpty) {
      _showError('Выберите хотя бы один филиал');
      return;
    }

    setState(() => _isLoading = true);

    final phone = _phoneController.text.trim();
    String? profileJson;
    if (_rezume != null) {
      profileJson = jsonEncode(_rezume);
    }

    final success = await _userService.createUser(
      username: _usernameController.text.trim(),
      login: _loginController.text.trim(),
      password: _passwordController.text.trim(),
      role: _selectedRole,
      filialIds: _selectedFilialIds.isNotEmpty ? _selectedFilialIds : null,
      phoneNumber: phone.isNotEmpty ? phone : null,
      profileJson: profileJson,
    );

    setState(() => _isLoading = false);

    if (success && mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пользователь добавлен')),
      );
    } else if (mounted) {
      _showError('Произошла ошибка');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Добавить пользователя'),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(onPressed: _saveUser, icon: const Icon(Icons.check)),
        ],
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator.adaptive())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Telefon raqam — birinchi
                    _buildPhoneField(),
                    const SizedBox(height: 16),

                    // Rezume xatosi
                    if (_rezumeError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_rezumeError!, style: TextStyle(color: Colors.red.shade900)),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Rezume preview
                    if (_rezume != null) ...[
                      _buildRezumePreview(_rezume!),
                      const SizedBox(height: 16),
                    ],

                    // Ism
                    _buildTextField(
                      controller: _usernameController,
                      label: 'Имя *',
                      icon: Icons.person,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Введите имя' : null,
                    ),
                    const SizedBox(height: 16),

                    // Login
                    _buildTextField(
                      controller: _loginController,
                      label: 'Логин *',
                      icon: Icons.account_circle,
                      hint: 'Номер телефона или логин',
                      validator: (v) => v == null || v.trim().isEmpty ? 'Введите логин' : null,
                    ),
                    const SizedBox(height: 16),

                    // Parol
                    _buildPasswordField(),
                    const SizedBox(height: 16),

                    // Filiallar
                    if (_selectedRole == 'worker' && _filials != null)
                      _buildFilialSection(),
                  ],
                ),
              ),
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
        labelText: 'Телефон',
        hintText: '998901234567',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.phone),
        suffixIcon: _fetchingRezume
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
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
                      width: 80, height: 100,
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
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if ((r['lavozim'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(r['lavozim'].toString(), style: const TextStyle(color: Colors.grey)),
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
            _kv('Языки', (r['tillar'] as List)
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
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  // ── Umumiy helper widgetlar ─────────────────────────────────────────────

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
        hintText: hint,
      ),
      validator: validator,
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: 'Пароль *',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: IconButton(
          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Введите пароль';
        if (v.length < 6) return 'Минимум 6 символов';
        return null;
      },
    );
  }

  Widget _buildFilialSection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Филиалы *', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (_selectedFilialIds.isEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Выбрать', style: TextStyle(fontSize: 12, color: Colors.red)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (_filials!.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Филиалы не найдены', style: TextStyle(color: Colors.grey)),
          )
        else
          ..._filials!.map((filial) => _buildSwitchRow(
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
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(title, style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
        CupertinoSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}
