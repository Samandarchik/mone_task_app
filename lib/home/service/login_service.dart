import 'package:flutter/material.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
import 'package:mone_task_app/home/model/login_model.dart';
import 'package:mone_task_app/home/service/api_service.dart';
import 'package:mone_task_app/home/ui/role_home.dart';
import 'package:mone_task_app/worker/model/user_model.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _passCtrl = TextEditingController();
  final _focus = FocusNode();
  TokenStorage tokenStorage = sl<TokenStorage>();

  bool _loading = false;
  bool _obscure = true;

  /// true — parol kiritilmagan (matn build ichida tarjima qilinadi).
  bool _emptyError = false;
  String? _error;
  String? _errorDetail;

  @override
  void dispose() {
    _passCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final password = _passCtrl.text.trim();
    if (password.isEmpty) {
      setState(() {
        _emptyError = true;
        _error = null;
        _errorDetail = null;
      });
      _focus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _emptyError = false;
      _error = null;
      _errorDetail = null;
    });

    try {
      final result = await ApiService().login(LoginModel(password: password));

      if (!mounted) return;
      setState(() => _loading = false);

      if (result['success'] == true && result['token'] != null) {
        await tokenStorage.putToken(result['token']);
        await tokenStorage.putUserData(result['user']);

        if (!mounted) return;
        context.pushAndRemove(
          landingForUser(
            UserModel.fromJson(Map<String, dynamic>.from(result['user'] as Map)),
          ),
        );
      } else {
        setState(() {
          _error =
              result['message']?.toString() ??
              tr("Parol noto'g'ri. Qaytadan kiriting.");
          _errorDetail = result['detail']?.toString();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = tr("Kirishda xatolik yuz berdi. Qayta urinib ko'ring.");
        _errorDetail = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final errorText = _emptyError ? tr('Parolni kiriting') : _error;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 72, 16, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Brend
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: AppRadius.lgAll,
                            boxShadow: AppShadows.raised,
                          ),
                          child: Icon(
                            Icons.task_alt_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                      SizedBox(height: AppSpacing.lg),
                      Text(
                        'MONE TASK',
                        textAlign: TextAlign.center,
                        style: t.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: AppSpacing.xs),
                      Text(
                        tr('Vazifalar nazorati tizimi'),
                        textAlign: TextAlign.center,
                        style: t.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: AppSpacing.xl),

                      // Karta
                      Container(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: AppRadius.lgAll,
                          border: Border.all(color: AppColors.border),
                          boxShadow: AppShadows.card,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              tr('Tizimga kirish'),
                              style: t.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: AppSpacing.xs),
                            Text(
                              tr('Sizga berilgan parolni kiriting'),
                              style: t.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            SizedBox(height: AppSpacing.xl),
                            Text(
                              tr('Parol'),
                              style: t.labelLarge?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            SizedBox(height: 6),
                            TextField(
                              controller: _passCtrl,
                              focusNode: _focus,
                              obscureText: _obscure,
                              enabled: !_loading,
                              autofocus: false,
                              textInputAction: TextInputAction.done,
                              onChanged: (_) {
                                if (_emptyError || _error != null) {
                                  setState(() {
                                    _emptyError = false;
                                    _error = null;
                                    _errorDetail = null;
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                hintText: tr('Parolni kiriting'),
                                prefixIcon: Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? tr("Parolni ko'rsatish")
                                      : tr('Parolni yashirish'),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                              onSubmitted: (_) => _login(),
                            ),
                            if (errorText != null) ...[
                              SizedBox(height: AppSpacing.md),
                              _ErrorBox(
                                message: errorText,
                                detail: _emptyError ? null : _errorDetail,
                              ),
                            ],
                            SizedBox(height: AppSpacing.xl),
                            FilledButton(
                              onPressed: _loading ? null : _login,
                              child: _loading
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(tr('Kirish')),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: AppSpacing.xl),
                      Text(
                        tr('Rejimni tanlang'),
                        textAlign: TextAlign.center,
                        style: t.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      SizedBox(height: AppSpacing.sm),
                      Center(child: ThemeToggle()),
                      SizedBox(height: AppSpacing.lg),
                      Text(
                        tr('Yozuvni tanlang'),
                        textAlign: TextAlign.center,
                        style: t.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      SizedBox(height: AppSpacing.sm),
                      Center(child: ScriptToggle()),
                      SizedBox(height: AppSpacing.lg),
                      Text(
                        tr("Parolni bilmasangiz, rahbaringizga murojaat qiling."),
                        textAlign: TextAlign.center,
                        style: t.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, this.detail});

  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: AppColors.danger,
            size: 20,
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: AppColors.danger,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  SizedBox(height: 2),
                  Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.danger.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
