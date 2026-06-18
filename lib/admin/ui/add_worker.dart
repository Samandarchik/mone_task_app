import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/service/user_service.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';

class AddWorkerPage extends StatefulWidget {
  const AddWorkerPage({super.key});

  @override
  State<AddWorkerPage> createState() => _AddWorkerPageState();
}

class _AddWorkerPageState extends State<AddWorkerPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  final String _selectedRole = 'worker';
  final List<int> _selectedFilialIds = [];
  final List<String> _selectedCategories = [];
  bool _isLoading = false;
  bool _obscurePassword = true;

  final UserService _userService = UserService();
  List<FilialModel>? _filials;
  List<CategoryModel>? _categories;
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final filials = await TaskViewService().fetchFilials();
      final categories = await TemplateService().fetchCategoriesList();
      setState(() {
        _filials = filials;
        _categories = categories;
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

  // ── Saqlash ─────────────────────────────────────────────────────────────

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRole == 'worker' && _selectedFilialIds.isEmpty) {
      _showError('Выберите хотя бы один филиал');
      return;
    }

    if (_selectedRole == 'worker' && _selectedCategories.isEmpty) {
      _showError('Выберите хотя бы одну категорию');
      return;
    }

    setState(() => _isLoading = true);

    final phone = _phoneController.text.trim();

    final success = await _userService.createUser(
      username: _usernameController.text.trim(),
      login: _loginController.text.trim(),
      password: _passwordController.text.trim(),
      role: _selectedRole,
      filialIds: _selectedFilialIds.isNotEmpty ? _selectedFilialIds : null,
      categories: _selectedCategories.isNotEmpty ? _selectedCategories : null,
      phoneNumber: phone.isNotEmpty ? phone : null,
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

                    // Kategoriyalar
                    if (_selectedRole == 'worker' && _categories != null)
                      _buildCategorySection(),
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
      decoration: const InputDecoration(
        labelText: 'Телефон',
        hintText: '998901234567',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.phone),
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

  Widget _buildCategorySection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Категории *', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (_selectedCategories.isEmpty) ...[
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
        if (_categories!.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Категории не найдены', style: TextStyle(color: Colors.grey)),
          )
        else
          ..._categories!.map((category) => _buildSwitchRow(
                title: category.name,
                value: _selectedCategories.contains(category.name),
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      _selectedCategories.add(category.name);
                    } else {
                      _selectedCategories.remove(category.name);
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
