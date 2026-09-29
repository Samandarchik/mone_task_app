import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/user_service.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
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
          connectTimeout: Duration(seconds: 20),
          receiveTimeout: Duration(seconds: 20),
        ),
      ).get(url, options: Options(validateStatus: (_) => true));

      if (resp.statusCode != 200) {
        setState(() {
          _rezumeError = '${tr('Rezyume topilmadi')} (${resp.statusCode})';
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
        _rezumeError = '${tr('Xatolik')}: $e';
        _fetchingRezume = false;
      });
    }
  }

  // ── Saqlash ─────────────────────────────────────────────────────────────

  Future<void> _saveUser() async {
    if (_usernameController.text.trim().isEmpty) {
      _showError(tr('Ismni kiriting'));
      return;
    }
    if (_selectedRole == 'worker' && _selectedFilialIds.isEmpty) {
      _showError(tr('Kamida bitta filialni tanlang'));
      return;
    }
    final password = _passwordController.text.trim();
    if (password.isNotEmpty && password.length < 6) {
      _showError(tr('Kirish kodi kamida 6 ta belgidan iborat boʻlsin'));
      return;
    }

    setState(() => _isLoading = true);

    final phone = _phoneController.text.trim();
    // Kod o'zgartirilgan bo'lsagina yuboramiz
    final changedPassword = password.isNotEmpty && password != widget.user.password
        ? password
        : null;
    final success = await _userService.updateUser(
      userId: widget.user.userId,
      username: _usernameController.text.trim(),
      role: _selectedRole,
      password: changedPassword,
      filialIds: _selectedFilialIds.isNotEmpty ? _selectedFilialIds : null,
      phoneNumber: phone.isNotEmpty ? phone : null,
      profileJson: _rezume != null ? jsonEncode(_rezume) : null,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      showAppSnack(context, tr('Saqlandi'), type: SnackType.success);
      Navigator.pop(context, true);
    } else {
      _showError(tr('Saqlab boʻlmadi. Qayta urinib koʻring'));
    }
  }

  Future<void> _forceLogout() async {
    final ok = await showConfirmDialog(
      context,
      title: tr('Hisobdan chiqarish'),
      message: tr(
        'Foydalanuvchi barcha qurilmalarda hisobdan chiqariladi. Davom etasizmi?',
      ),
      confirmLabel: tr('Chiqarish'),
      destructive: true,
    );
    if (!ok) return;
    await LogOutService().logOutUser(widget.user.userId);
    if (!mounted) return;
    showAppSnack(
      context,
      tr('Foydalanuvchi hisobdan chiqarildi'),
      type: SnackType.success,
    );
  }

  void _showError(String message) {
    showAppSnack(context, message, type: SnackType.error);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Foydalanuvchini tahrirlash'))),
      body: FutureBuilder<List<FilialModel>>(
        future: _filialsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return AppLoader();
          }
          if (!snapshot.hasData) {
            return AppErrorState(
              onRetry: () => setState(() {
                _filialsFuture = TaskViewService().fetchFilials();
              }),
            );
          }

          final filials = snapshot.data!;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: EdgeInsets.all(AppSpacing.lg),
                children: [
                  _card([
                    // Telefon — rezumeni yangilash uchun
                    _buildPhoneField(),
                    if (_rezumeError != null) ...[
                      SizedBox(height: AppSpacing.md),
                      Container(
                        padding: EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.dangerSoft,
                          borderRadius: AppRadius.mdAll,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: AppColors.danger,
                              size: 20,
                            ),
                            SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _rezumeError!,
                                style: TextStyle(color: AppColors.danger),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_rezume != null) ...[
                      SizedBox(height: AppSpacing.md),
                      _buildRezumePreview(_rezume!),
                    ],
                  ]),
                  SizedBox(height: AppSpacing.md),
                  _card([
                    TextField(
                      controller: _usernameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: tr('Ism'),
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    SizedBox(height: AppSpacing.lg),
                    // Kod / parol — foydalanuvchi shu bilan tizimga kiradi
                    _buildPasswordField(),
                  ]),
                  if (_selectedRole == 'worker') ...[
                    SizedBox(height: AppSpacing.md),
                    _card([
                      _buildSectionTitle(tr('Filiallar')),
                      SizedBox(height: AppSpacing.xs),
                      Text(
                        tr('Xodim qaysi filiallarda ishlashini belgilang'),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: AppSpacing.sm),
                      ...filials.map(
                        (filial) => _buildSwitchRow(
                          title: displayName(filial.name),
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
                        ),
                      ),
                    ]),
                  ],
                  SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: BorderSide(color: AppColors.border),
                    ),
                    onPressed: _forceLogout,
                    icon: Icon(Icons.logout_rounded),
                    label: Text(tr('Hisobdan chiqarish')),
                  ),
                  SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(tr('Saqlash')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  // ── Telefon maydoni ─────────────────────────────────────────────────────

  Widget _buildPhoneField() {
    return TextField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
      decoration: InputDecoration(
        labelText: tr('Telefon'),
        helperText: tr('Rezyumeni yangilash uchun raqamni kiriting'),
        hintText: '998901234567',
        prefixIcon: Icon(Icons.phone_outlined),
        suffixIcon: _fetchingRezume
            ? Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: Icon(Icons.refresh_rounded),
                onPressed: _fetchRezume,
                tooltip: tr('Rezyumeni yangilash'),
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
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photoUrl != null)
                ClipRRect(
                  borderRadius: AppRadius.smAll,
                  child: Image.network(
                    photoUrl,
                    width: 72,
                    height: 90,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 72,
                      height: 90,
                      color: AppColors.border,
                      child: Icon(
                        Icons.person_rounded,
                        size: 36,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              if (photoUrl != null) SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fio.isEmpty ? tr('Ism topilmadi') : trData(fio),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if ((r['lavozim'] ?? '').toString().isNotEmpty) ...[
                      SizedBox(height: 2),
                      Text(
                        trData(r['lavozim'].toString()),
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                    SizedBox(height: 4),
                    Text(
                      (r['telefon'] ?? '').toString(),
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Divider(height: 24),
          _kv(tr('Tugʻilgan sana'), r['tugilgan_sana'], raw: true),
          _kv(
            tr('Boʻyi / vazni'),
            '${r['boy_sm'] ?? '?'} ${tr('sm')} / ${r['vazn_kg'] ?? '?'} ${tr('kg')}',
            raw: true,
          ),
          _kv(tr('Manzil'), r['yashash_manzili']),
          _kv(tr('Moʻljal'), r['moljal']),
          _kv(tr('Umumiy tajriba'), r['umumiy_tajriba']),
          _kv(tr('Chet eldagi tajriba'), r['chet_el_tajribasi']),
          _kv(tr('Maʼlumoti'), r['malumot']),
          _kv(tr('Oilaviy holati'), r['oilaviy_holat']),
          if (r['tillar'] is List)
            _kv(
              tr('Tillar'),
              (r['tillar'] as List)
                  .map((t) => '${(t as Map)['til']}: ${t['daraja']}')
                  .join(', '),
            ),
          if ((r['qoshimcha'] ?? '').toString().isNotEmpty)
            _kv(tr('Qoʻshimcha'), r['qoshimcha']),
          if ((r['tg_username'] ?? '').toString().isNotEmpty)
            _kv('Telegram', '@${r['tg_username']}', raw: true),
        ],
      ),
    );
  }

  Widget _kv(String label, dynamic value, {bool raw = false}) {
    final v = (value ?? '').toString();
    if (v.isEmpty) return SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              raw ? v : trData(v),
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: tr('Kirish kodi'),
        hintText: tr('Ilovaga kirish uchun kod'),
        helperText: tr('Kamida 6 ta belgi'),
        prefixIcon: Icon(Icons.key_outlined),
        suffixIcon: IconButton(
          tooltip: _obscurePassword ? tr('Koʻrsatish') : tr('Yashirish'),
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}
