import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/service/user_service.dart';
import 'package:mone_task_app/admin/ui/user_edit_dialog.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';

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

  // Yangi foydalanuvchi har doim "worker" (Nazoratchi) sifatida yaratiladi —
  // rolni keyin ro'yxatdan o'zgartirish mumkin.
  final String _selectedRole = 'worker';
  final List<int> _selectedFilialIds = [];
  final List<String> _selectedCategories = [];
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _triedSubmit = false;

  final UserService _userService = UserService();
  List<FilialModel>? _filials;
  List<CategoryModel>? _categories;
  bool _isLoadingData = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoadingData = true;
      _loadError = false;
    });
    try {
      final filials = await TaskViewService().fetchFilials();
      final categories = await TemplateService().fetchCategoriesList();
      if (!mounted) return;
      setState(() {
        _filials = filials;
        _categories = categories;
        _isLoadingData = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingData = false;
        _loadError = true;
      });
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

  bool get _isWorker => _selectedRole == 'worker';

  // ── Saqlash ─────────────────────────────────────────────────────────────

  Future<void> _saveUser() async {
    setState(() => _triedSubmit = true);
    final formOk = _formKey.currentState!.validate();
    if (!formOk) return;

    if (_isWorker && _selectedFilialIds.isEmpty) {
      showAppSnack(
        context,
        tr('Kamida bitta filialni tanlang'),
        type: SnackType.error,
      );
      return;
    }

    if (_isWorker && _selectedCategories.isEmpty) {
      showAppSnack(
        context,
        tr('Kamida bitta kategoriyani tanlang'),
        type: SnackType.error,
      );
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

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      showAppSnack(
        context,
        tr("Foydalanuvchi qo'shildi"),
        type: SnackType.success,
      );
      Navigator.pop(context, true);
    } else {
      showAppSnack(
        context,
        tr("Saqlab bo'lmadi. Qayta urinib ko'ring."),
        type: SnackType.error,
      );
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Yangi foydalanuvchi'))),
      body: _isLoadingData
          ? AppLoader()
          : _loadError
          ? AppErrorState(onRetry: _loadData)
          : Form(
              key: _formKey,
              // SingleChildScrollView — barcha maydonlar doim quriladi,
              // shuning uchun Form.validate() ekrandan tashqaridagilarni ham tekshiradi.
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 720),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _card(
                          title: tr("Asosiy ma'lumotlar"),
                          children: [
                            _buildPhoneField(),
                            SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _usernameController,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: '${tr('Ism')} *',
                                hintText: tr('Masalan: Aliyev Vali'),
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? tr('Ismni kiriting')
                                  : null,
                            ),
                            SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _loginController,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: '${tr('Login')} *',
                                hintText: tr('Telefon raqami yoki login'),
                                prefixIcon: Icon(Icons.alternate_email_rounded),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? tr('Loginni kiriting')
                                  : null,
                            ),
                            SizedBox(height: AppSpacing.md),
                            _buildPasswordField(),
                            SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                Text(
                                  tr('Rol'),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                                SizedBox(width: AppSpacing.sm),
                                StatusBadge(
                                  label: userRoleLabel(_selectedRole),
                                  color: userRoleColors(_selectedRole).$1,
                                  background: userRoleColors(_selectedRole).$2,
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (_isWorker && _filials != null) ...[
                          SizedBox(height: AppSpacing.lg),
                          _buildChipSection(
                            title: '${tr('Filiallar')} *',
                            emptyText: tr("Filiallar yo'q"),
                            selectedCount: _selectedFilialIds.length,
                            children: _filials!.map((f) {
                              final sel = _selectedFilialIds.contains(
                                f.filialId,
                              );
                              return FilterChip(
                                label: Text(displayName(f.name)),
                                selected: sel,
                                onSelected: (v) => setState(() {
                                  v
                                      ? _selectedFilialIds.add(f.filialId)
                                      : _selectedFilialIds.remove(f.filialId);
                                }),
                              );
                            }).toList(),
                            onSelectAll: () => setState(() {
                              final all = _filials!.map((f) => f.filialId);
                              if (_selectedFilialIds.length ==
                                  _filials!.length) {
                                _selectedFilialIds.clear();
                              } else {
                                _selectedFilialIds
                                  ..clear()
                                  ..addAll(all);
                              }
                            }),
                            allSelected:
                                _filials!.isNotEmpty &&
                                _selectedFilialIds.length == _filials!.length,
                            errorText: tr('Kamida bitta filialni tanlang'),
                          ),
                        ],
                        if (_isWorker && _categories != null) ...[
                          SizedBox(height: AppSpacing.lg),
                          _buildChipSection(
                            title: '${tr('Kategoriyalar')} *',
                            emptyText: tr("Kategoriyalar yo'q"),
                            selectedCount: _selectedCategories.length,
                            children: _categories!.map((c) {
                              final sel = _selectedCategories.contains(c.name);
                              return FilterChip(
                                label: Text(displayName(c.name)),
                                selected: sel,
                                onSelected: (v) => setState(() {
                                  v
                                      ? _selectedCategories.add(c.name)
                                      : _selectedCategories.remove(c.name);
                                }),
                              );
                            }).toList(),
                            onSelectAll: () => setState(() {
                              if (_selectedCategories.length ==
                                  _categories!.length) {
                                _selectedCategories.clear();
                              } else {
                                _selectedCategories
                                  ..clear()
                                  ..addAll(_categories!.map((c) => c.name));
                              }
                            }),
                            allSelected:
                                _categories!.isNotEmpty &&
                                _selectedCategories.length ==
                                    _categories!.length,
                            errorText: tr('Kamida bitta kategoriyani tanlang'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: _isLoadingData || _loadError
          ? null
          : SafeArea(
              minimum: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 720),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _saveUser,
                      child: _isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(tr('Saqlash')),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ── Bo'limlar ───────────────────────────────────────────────────────────

  Widget _card({String? title, required List<Widget> children}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: AppSpacing.md),
            ],
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
      decoration: InputDecoration(
        labelText: tr('Telefon'),
        hintText: '998901234567',
        prefixIcon: Icon(Icons.phone_outlined),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: '${tr('Parol')} *',
        helperText: tr('Kamida 6 ta belgi'),
        prefixIcon: Icon(Icons.key_rounded),
        suffixIcon: IconButton(
          tooltip: _obscurePassword
              ? tr("Parolni ko'rsatish")
              : tr('Parolni yashirish'),
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return tr('Parolni kiriting');
        if (v.length < 6) {
          return tr('Parol kamida 6 ta belgidan iborat boʻlsin');
        }
        return null;
      },
    );
  }

  Widget _buildChipSection({
    required String title,
    required String emptyText,
    required int selectedCount,
    required List<Widget> children,
    required VoidCallback onSelectAll,
    required bool allSelected,
    required String errorText,
  }) {
    final t = Theme.of(context).textTheme;
    final showError = _triedSubmit && selectedCount == 0;
    return _card(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (children.isNotEmpty)
              TextButton(
                onPressed: onSelectAll,
                style: TextButton.styleFrom(
                  minimumSize: Size(0, 36),
                  padding: EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  allSelected ? tr('Hammasini bekor qilish') : tr('Hammasi'),
                ),
              ),
          ],
        ),
        Text(
          selectedCount == 0
              ? tr('Hali tanlanmagan')
              : '$selectedCount ${tr('ta tanlandi')}',
          style: t.bodySmall?.copyWith(
            color: showError ? AppColors.danger : AppColors.textTertiary,
          ),
        ),
        SizedBox(height: AppSpacing.md),
        if (children.isEmpty)
          Text(
            emptyText,
            style: t.bodyMedium?.copyWith(color: AppColors.textTertiary),
          )
        else
          Wrap(spacing: 8, runSpacing: 8, children: children),
        if (showError) ...[
          SizedBox(height: AppSpacing.sm),
          Text(
            errorText,
            style: t.bodySmall?.copyWith(color: AppColors.danger),
          ),
        ],
      ],
    );
  }
}
