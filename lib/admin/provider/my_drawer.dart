import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/get_excel_ui.dart';
import 'package:mone_task_app/admin/ui/all_task_ui.dart';
import 'package:mone_task_app/admin/ui/user_list_page.dart';
import 'package:mone_task_app/admin/ui/video_cache_manager_page.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
import 'package:mone_task_app/shared/widgets/user_avatar.dart';
import 'package:mone_task_app/worker/model/user_model.dart';

/// Rol nomi (o'zbekcha, tanlangan alifboda).
String roleLabel(String? role) => switch (role) {
  'super_admin' => tr('Super admin'),
  'checker' => tr('Tekshiruvchi'),
  'worker' => tr('Nazoratchi'),
  _ => role ?? '',
};

class MyDrawer extends StatelessWidget {
  const MyDrawer({
    super.key,
    required this.categories,
    required this.user,
    required this.onLogout,
    this.onClearCache,
    this.onSwitchFilial,
  });

  final List<FilialModel> categories;
  final UserModel? user;
  final VoidCallback onLogout;

  /// Berilsa — "Keshni tozalash" bandi ko'rsatiladi.
  final VoidCallback? onClearCache;

  /// Berilsa — "Filialni almashtirish" bandi ko'rsatiladi.
  final VoidCallback? onSwitchFilial;

  void _go(BuildContext context, Widget page) {
    Navigator.pop(context);
    context.push(page);
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: tr('Hisobdan chiqish'),
      message: tr('Hisobdan chiqishni xohlaysizmi?'),
      confirmLabel: tr('Chiqish'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    Navigator.pop(context);
    onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = displayName(user?.fullName);
    final isChecker = user?.role == 'checker';

    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Foydalanuvchi ma'lumoti ──────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  UserAvatar(user: user, radius: 26),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isNotEmpty ? name : (user?.username ?? ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            roleLabel(user?.role),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1),

            // ── Menyu elementlari ────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                children: [
                  _DrawerItem(
                    icon: CupertinoIcons.list_bullet,
                    label: tr('Barcha vazifalar'),
                    onTap: () => _go(
                      context,
                      TemplateTaskAdminUi(
                        name: user?.username ?? '',
                        category: categories,
                      ),
                    ),
                  ),
                  // Tekshiruvchi foydalanuvchilar ro'yxatini ko'ra olmaydi.
                  if (!isChecker)
                    _DrawerItem(
                      icon: CupertinoIcons.person_2,
                      label: tr('Barcha foydalanuvchilar'),
                      onTap: () =>
                          _go(context, UsersPage(filialModel: categories)),
                    ),
                  _DrawerItem(
                    icon: CupertinoIcons.doc_chart,
                    label: tr('Hisobotlar'),
                    onTap: () =>
                        _go(context, ExcelReportPage(filials: categories)),
                  ),
                  if (onSwitchFilial != null)
                    _DrawerItem(
                      icon: Icons.swap_horiz_rounded,
                      label: tr('Filialni almashtirish'),
                      onTap: () {
                        Navigator.pop(context);
                        onSwitchFilial!();
                      },
                    ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Divider(height: 1),
                  ),
                  _DrawerItem(
                    icon: CupertinoIcons.videocam,
                    label: tr('Video kesh'),
                    onTap: () => _go(context, VideoCacheManagerPage()),
                  ),
                  if (onClearCache != null)
                    _DrawerItem(
                      icon: CupertinoIcons.trash,
                      label: tr('Keshni tozalash'),
                      onTap: () {
                        Navigator.pop(context);
                        onClearCache!();
                      },
                    ),
                ],
              ),
            ),

            // ── Yozuv (alifbo) ───────────────────────────────────────────
            Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 16, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.contrast_rounded,
                    size: 22,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Text(tr('Rejim'), style: t.bodyLarge),
                  ),
                  ThemeToggle(compact: true),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.translate_rounded,
                    size: 22,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Text(tr('Yozuv'), style: t.bodyLarge),
                  ),
                  ScriptToggle(compact: true),
                ],
              ),
            ),

            // ── Chiqish ──────────────────────────────────────────────────
            _DrawerItem(
              icon: Icons.logout_rounded,
              label: tr('Hisobdan chiqish'),
              color: AppColors.danger,
              onTap: () => _confirmLogout(context),
            ),
            SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        onTap: onTap,
        minTileHeight: 48,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        leading: Icon(icon, size: 22, color: color ?? AppColors.textSecondary),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: c,
          ),
        ),
      ),
    );
  }
}
