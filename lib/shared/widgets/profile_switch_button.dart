import 'package:flutter/material.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/core/network/ws_service.dart';
import 'package:mone_task_app/home/model/login_model.dart';
import 'package:mone_task_app/home/service/api_service.dart';
import 'package:mone_task_app/home/ui/role_home.dart';
import 'package:mone_task_app/worker/model/user_model.dart';

/// Super admin login kodi ([code]) bilan boshqa akkauntga kiradi. Super admin
/// sessiyasi saqlanadi — [ProfileSwitchButton] orqali orqaga qaytiladi.
/// Xato bo'lsa — xabar matni, muvaffaqiyatli bo'lsa null.
Future<String?> switchToAccount(BuildContext context, String code) async {
  final result = await ApiService().login(LoginModel(password: code));
  if (result['success'] != true || result['token'] == null) {
    return result['message']?.toString() ??
        result['error']?.toString() ??
        'Неверный код';
  }

  final data = Map<String, dynamic>.from(result['user'] as Map);
  final ts = sl<TokenStorage>();
  final current = ts.getUserData();
  // O'z akkauntiga qayta kirish ma'nosiz (boshqa super adminga o'tsa bo'ladi)
  final adminId = (ts.getSuperAdminSessionUser() ?? current)?.userId;
  if (data['userId'] == adminId && current?.role == 'super_admin') {
    return 'Это ваш аккаунт';
  }

  // Akkauntdan akkauntga o'tilsa ham asl super admin sessiyasi saqlanib qoladi
  if (ts.getSuperAdminSessionUser() == null && current?.role == 'super_admin') {
    await ts.saveSuperAdminSession();
  }
  await ts.putToken(result['token']);
  await ts.putUserData(data);
  WsService().disconnect();
  if (context.mounted) {
    context.pushAndRemove(landingForUser(UserModel.fromJson(data)));
  }
  return null;
}

/// Foydalanuvchilar ro'yxatidan [user] nomidan kirish (uning paroli bilan).
Future<void> loginAsUser(BuildContext context, UserModel user) async {
  final messenger = ScaffoldMessenger.of(context);
  if (user.password.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('У пользователя нет пароля')),
    );
    return;
  }
  final error = await switchToAccount(context, user.password);
  if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
}

/// AppBar'dagi oddiy dumaloq profil tugmasi.
///
/// Super admin:
/// - birinchi bosishda login kodi so'raladi va shu akkauntga o'tiladi;
///   kod eslab qolinadi — keyingi safar bir bosishda o'sha akkauntga o'tadi;
/// - bosib turilsa — kod qaytadan so'raladi (boshqa akkaunt tanlash).
///
/// Super admin o'tgan akkauntda — bosilsa super adminga qaytadi
/// (oddiy akkauntda bosib turish hech narsa qilmaydi — kod so'ralmaydi).
class ProfileSwitchButton extends StatelessWidget {
  const ProfileSwitchButton({super.key});

  @override
  Widget build(BuildContext context) {
    final ts = sl<TokenStorage>();
    final inLinkedAccount = ts.getSuperAdminSessionUser() != null;
    if (!inLinkedAccount && ts.getUserData()?.role != 'super_admin') {
      return const SizedBox.shrink();
    }

    return Tooltip(
      message: inLinkedAccount
          ? 'Вернуться к супер админу'
          : 'Сменить аккаунт (удерживайте — ввести код)',
      child: SizedBox.square(
        dimension: 36,
        child: Material(
          color: const Color(0xFFEFF4FF),
          shape: const CircleBorder(
            side: BorderSide(color: Color(0xFFBFD3FE), width: 1.5),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => inLinkedAccount
                ? _returnToSuperAdmin(context)
                : _switchToLinked(context),
            // Kod faqat super admin akkauntida so'raladi
            onLongPress: ts.getUserData()?.role == 'super_admin'
                ? () => _askCodeAndSwitch(context)
                : null,
            child: const Icon(
              Icons.person_rounded,
              size: 22,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _returnToSuperAdmin(BuildContext context) async {
    final user = await sl<TokenStorage>().restoreSuperAdminSession();
    if (user == null || !context.mounted) return;
    WsService().disconnect();
    context.pushAndRemove(landingForUser(user));
  }

  /// Eslab qolingan kod bo'lsa — darhol o'sha akkauntga, bo'lmasa kod so'raladi.
  Future<void> _switchToLinked(BuildContext context) async {
    final code = sl<TokenStorage>().getLinkedAccountCode();
    if (code.isEmpty) return _askCodeAndSwitch(context);

    final error = await switchToAccount(context, code);
    if (error == null || !context.mounted) return;
    // Kod eskirgan (parol o'zgargan) — qaytadan so'raymiz
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    await _askCodeAndSwitch(context);
  }

  /// Kod so'raladigan kichik oyna — tugmaning tagida, o'ng chetiga tekislanib.
  Future<void> _askCodeAndSwitch(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final right = (screenWidth - origin.dx - box.size.width).clamp(
      8.0,
      screenWidth,
    );

    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (_) => Stack(
        children: [
          Positioned(
            top: origin.dy + box.size.height + 8,
            right: right,
            child: const _CodeDialog(),
          ),
        ],
      ),
    );
  }
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog();

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Введите код');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    // Kod eslab qolinadi — keyingi safar bir bosishda o'tiladi
    final ts = sl<TokenStorage>();
    final previous = ts.getLinkedAccountCode();
    await ts.putLinkedAccountCode(code);
    if (!mounted) return;
    final error = await switchToAccount(context, code);
    if (error != null) {
      await ts.putLinkedAccountCode(previous);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 250,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Код аккаунта',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: true,
                obscureText: _obscure,
                enabled: !_loading,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Введите код',
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                  errorText: _error,
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Войти'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
