import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/service/user_service.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
import 'package:mone_task_app/worker/model/user_model.dart';

/// Ilovadagi rollar (server qiymatlari) — ko'rsatish tartibida.
const List<String> kUserRoles = ['super_admin', 'checker', 'worker'];

/// Rol nomi o'zbek tilida (joriy alifboda).
/// super_admin → Super admin, checker (Корректор) → Tekshiruvchi,
/// worker (Ревизор) → Nazoratchi.
String userRoleLabel(String role) => switch (role) {
  'super_admin' => tr('Super admin'),
  'checker' => tr('Tekshiruvchi'),
  'worker' => tr('Nazoratchi'),
  _ => role,
};

/// Rol belgisi ranglari (matn rangi, fon rangi).
(Color, Color) userRoleColors(String role) => switch (role) {
  'super_admin' => (AppColors.warning, AppColors.warningSoft),
  'checker' => (AppColors.info, AppColors.infoSoft),
  _ => (AppColors.primary, AppColors.primarySoft),
};

/// Foydalanuvchini bitta tap bilan tahrirlash dialogi:
/// ism, telefon, parol, rol, filiallar, kategoriyalar va rezyumeni
/// HR'dan yangilash.
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
      // Saqlash paytida tashqariga bosib yopilsa natija (true) yo'qolardi.
      barrierDismissible: false,
      builder: (_) => UserEditDialog(user: user, filials: filials),
    );
  }

  @override
  State<UserEditDialog> createState() => _UserEditDialogState();
}

enum _RezumeState { none, ok, error }

class _UserEditDialogState extends State<UserEditDialog> {
  static const String _rezumeBaseUrl = 'https://hr.monebakeryuz.uz';

  final UserService _userService = UserService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _passwordController;
  late String _selectedRole;
  late List<int> _selectedFilialIds;
  late List<String> _selectedCategories;

  List<CategoryModel> _categories = [];
  bool _loadingCategories = true;

  Map<String, dynamic>? _rezume;
  bool _replacingRezume = false;
  _RezumeState _rezumeState = _RezumeState.none;
  String? _rezumeDetail; // xatolik tafsiloti (kod / exception)
  String? _rezumeKey; // tr() uchun kalit (build ichida tarjima qilinadi)
  bool _saving = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.username);
    _phoneController = TextEditingController(
      text: widget.user.phoneNumber ?? widget.user.login,
    );
    _passwordController = TextEditingController(text: widget.user.password);
    _selectedRole = widget.user.role;
    _selectedFilialIds = List<int>.from(widget.user.filialIds ?? []);
    _selectedCategories = List<String>.from(widget.user.categories ?? []);
    _rezume = widget.user.profile;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await TemplateService().fetchCategoriesList();
      if (mounted) setState(() => _categories = categories);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingCategories = false);
    }
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
      setState(() {
        _rezumeState = _RezumeState.error;
        _rezumeKey = 'Avval telefon raqamini kiriting';
        _rezumeDetail = null;
      });
      return;
    }

    setState(() {
      _replacingRezume = true;
      _rezumeState = _RezumeState.none;
    });

    try {
      final normalized = phone.startsWith('+') || phone.startsWith('998')
          ? phone
          : '998$phone';
      final url = '$_rezumeBaseUrl/api/public/rezume-by-phone/$normalized';
      final resp = await Dio(
        BaseOptions(
          connectTimeout: Duration(seconds: 20),
          receiveTimeout: Duration(seconds: 20),
        ),
      ).get(url, options: Options(validateStatus: (_) => true));
      if (!mounted) return;

      if (resp.statusCode != 200) {
        setState(() {
          _rezumeState = _RezumeState.error;
          _rezumeKey = 'Rezyume topilmadi';
          _rezumeDetail = '${resp.statusCode}';
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
        _rezumeState = _RezumeState.ok;
        _rezumeKey = 'Rezyume yangilandi';
        _rezumeDetail = null;
        _replacingRezume = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rezumeState = _RezumeState.error;
        _rezumeKey = 'Xatolik';
        _rezumeDetail = '$e';
        _replacingRezume = false;
      });
    }
  }

  // ── Saqlash ─────────────────────────────────────────────────────────────

  bool get _isWorker => _selectedRole == 'worker';

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isWorker && _selectedFilialIds.isEmpty) {
      showAppSnack(
        context,
        tr('Kamida bitta filialni tanlang'),
        type: SnackType.error,
      );
      return;
    }

    final name = _nameController.text.trim();
    final password = _passwordController.text.trim();

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
      showAppSnack(context, tr('Saqlandi'), type: SnackType.success);
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
    final t = Theme.of(context).textTheme;
    final title = widget.user.fullName.isNotEmpty
        ? trData(widget.user.fullName)
        : widget.user.username;

    return PopScope(
      // Saqlash tugaguncha orqaga tugmasi bilan ham yopilmaydi.
      canPop: !_saving,
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520, maxHeight: 780),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sarlavha
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('Foydalanuvchini tahrirlash'),
                              style: t.labelMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              title,
                              style: t.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.user.login.isNotEmpty)
                              Text(
                                '@${widget.user.login}',
                                style: t.bodySmall?.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Yopish'),
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context, false),
                        icon: Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: '${tr('Ism')} *',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? tr('Ismni kiriting')
                              : null,
                        ),
                        SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: tr('Telefon'),
                            hintText: '998901234567',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: tr('Parol'),
                            helperText: tr(
                              "O'zgartirmasangiz, eski parol qoladi",
                            ),
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
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: (v) {
                            final p = (v ?? '').trim();
                            if (p.isNotEmpty && p.length < 4) {
                              return tr(
                                'Parol kamida 4 ta belgidan iborat boʻlsin',
                              );
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: AppSpacing.xl),
                        _label(tr('Rol')),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: kUserRoles.map((r) {
                            return ChoiceChip(
                              label: Text(userRoleLabel(r)),
                              selected: _selectedRole == r,
                              onSelected: (_) =>
                                  setState(() => _selectedRole = r),
                            );
                          }).toList(),
                        ),
                        if (_isWorker) ...[
                          SizedBox(height: AppSpacing.xl),
                          _label(
                            '${tr('Filiallar')} *',
                            count: _selectedFilialIds.length,
                          ),
                          if (widget.filials.isEmpty)
                            _hint(tr("Filiallar yo'q"))
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: widget.filials.map((f) {
                                final selected = _selectedFilialIds.contains(
                                  f.filialId,
                                );
                                return FilterChip(
                                  label: Text(displayName(f.name)),
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
                          SizedBox(height: AppSpacing.xl),
                          _label(
                            tr('Kategoriyalar'),
                            count: _selectedCategories.length,
                          ),
                          if (_loadingCategories)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: LinearProgressIndicator(minHeight: 2),
                            )
                          else if (_categories.isEmpty)
                            _hint(tr("Kategoriyalar yo'q"))
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _categories.map((c) {
                                final selected = _selectedCategories.contains(
                                  c.name,
                                );
                                return FilterChip(
                                  label: Text(displayName(c.name)),
                                  selected: selected,
                                  onSelected: (v) => setState(() {
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
                        SizedBox(height: AppSpacing.xl),
                        _label(tr('Rezyume')),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _replacingRezume ? null : _replaceRezume,
                            icon: _replacingRezume
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(Icons.sync_rounded, size: 18),
                            label: Text(tr("Rezyumeni HR'dan yangilash")),
                          ),
                        ),
                        if (_rezumeState != _RezumeState.none &&
                            _rezumeKey != null) ...[
                          SizedBox(height: AppSpacing.sm),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _rezumeState == _RezumeState.ok
                                    ? Icons.check_circle_rounded
                                    : Icons.error_outline_rounded,
                                size: 16,
                                color: _rezumeState == _RezumeState.ok
                                    ? AppColors.success
                                    : AppColors.danger,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _rezumeDetail == null
                                      ? tr(_rezumeKey!)
                                      : '${tr(_rezumeKey!)} ($_rezumeDetail)',
                                  style: t.bodySmall?.copyWith(
                                    color: _rezumeState == _RezumeState.ok
                                        ? AppColors.success
                                        : AppColors.danger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Divider(height: 1),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context, false),
                          child: Text(tr('Bekor qilish')),
                        ),
                      ),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
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
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text, {int? count}) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Flexible(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (count != null && count > 0) ...[
            SizedBox(width: 8),
            Text(
              '$count ${tr('ta tanlandi')}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hint(String text) => Padding(
    padding: EdgeInsets.symmetric(vertical: 4),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
    ),
  );
}
