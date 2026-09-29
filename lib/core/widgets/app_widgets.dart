import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';

/// Lotin / Kirill almashtirgich. Bosilganda butun ilova darhol yangilanadi.
///
/// [compact] — AppBar uchun kichik variant.
class ScriptToggle extends StatelessWidget {
  const ScriptToggle({super.key, this.compact = false, this.onDark = false});

  final bool compact;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppScript>(
      valueListenable: AppScriptController.instance,
      builder: (context, script, _) {
        final h = compact ? 32.0 : 40.0;
        Widget seg(AppScript s, String label) {
          final selected = script == s;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => AppScriptController.instance.set(s),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? (onDark ? Colors.white : AppColors.surface)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(h / 2),
                    boxShadow: selected ? AppShadows.card : null,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: compact ? 12.5 : 14,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppColors.primary
                          : (onDark ? Colors.white70 : AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Container(
          height: h,
          width: compact ? 112 : 180,
          padding: EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: onDark
                ? Colors.white.withValues(alpha: 0.14)
                : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(h / 2),
          ),
          child: Row(
            children: [
              seg(AppScript.latin, compact ? 'Lot' : 'Lotin'),
              seg(AppScript.cyrillic, compact ? 'Кир' : 'Кирилл'),
            ],
          ),
        );
      },
    );
  }
}

/// Bo'sh holat: ikonka + sarlavha + izoh + (ixtiyoriy) tugma.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: AppColors.primary),
            ),
            SizedBox(height: AppSpacing.lg),
            Text(title, style: t.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                style: t.bodyMedium?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: AppSpacing.lg),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Xatolik holati — "Qayta urinish" tugmasi bilan.
class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.wifi_off_rounded,
      title: tr("Ma'lumotlarni yuklab bo'lmadi"),
      message:
          message ?? tr("Internet aloqasini tekshirib, qayta urinib ko'ring."),
      actionLabel: onRetry != null ? tr('Qayta urinish') : null,
      onAction: onRetry,
    );
  }
}

/// Markazdagi yuklanish indikatori.
class AppLoader extends StatelessWidget {
  const AppLoader({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(strokeWidth: 2.6));
}

/// Bo'lim sarlavhasi (ro'yxatlar ustida).
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Holat belgisi (chip): rangli fon + matn.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  factory StatusBadge.forTask(int status) => StatusBadge(
    label: taskStatusLabel(status),
    color: statusColor(status),
    background: statusSoftColor(status),
  );

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vazifa holati nomi (1 — bajarilmagan, 2 — tekshiruvda, 3 — bajarilgan).
String taskStatusLabel(int status) => switch (status) {
  3 => tr('Bajarildi'),
  2 => tr('Tekshiruvda'),
  _ => tr('Bajarilmagan'),
};

enum SnackType { info, success, error }

/// Bir xil ko'rinishdagi xabar (snackbar).
void showAppSnack(
  BuildContext context,
  String message, {
  SnackType type = SnackType.info,
}) {
  final (icon, color) = switch (type) {
    SnackType.success => (Icons.check_circle_rounded, AppColors.success),
    SnackType.error => (Icons.error_rounded, AppColors.danger),
    SnackType.info => (Icons.info_rounded, AppColors.info),
  };
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// Tasdiqlash oynasi. `true` — tasdiqlandi.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message != null ? Text(message) : null,
      actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(cancelLabel ?? tr('Bekor qilish')),
              ),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                    : null,
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel ?? tr('Tasdiqlash')),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Mikrofon / kamera ruxsatini o'zbek tilida tushuntirib so'raydi.
///
/// Tizim oynasidan oldin nima uchun kerakligini ko'rsatadi; butunlay rad
/// etilgan bo'lsa — sozlamalarni ochishni taklif qiladi.
/// `true` — ruxsat bor.
Future<bool> ensurePermission(
  BuildContext context,
  Permission permission,
) async {
  var status = await permission.status;
  if (status.isGranted || status.isLimited) return true;
  if (!context.mounted) return false;

  final isMic = permission == Permission.microphone;
  final title = isMic
      ? tr('Mikrofonga ruxsat bering')
      : tr('Kameraga ruxsat bering');
  final message = isMic
      ? tr(
          "Ovozli xabar yozish uchun mikrofon kerak. Keyingi oynada «Ruxsat berish»ni tanlang.",
        )
      : tr(
          "Vazifa bajarilganini video bilan tasdiqlash uchun kamera kerak. Keyingi oynada «Ruxsat berish»ni tanlang.",
        );

  if (status.isPermanentlyDenied) {
    final open = await showConfirmDialog(
      context,
      title: title,
      message: tr(
        "Ruxsat avval rad etilgan. Uni telefon sozlamalaridan yoqing.",
      ),
      confirmLabel: tr('Sozlamalarni ochish'),
    );
    if (open) await openAppSettings();
    return false;
  }

  final ok = await showConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: tr('Davom etish'),
    cancelLabel: tr('Hozir emas'),
  );
  if (!ok) return false;
  status = await permission.request();
  if (status.isGranted || status.isLimited) return true;

  // Tizim oynasi ko'rsatilmasdan rad etildi (Android: "Boshqa so'ralmasin",
  // iOS: cheklangan) — faqat sozlamalar orqali yoqish mumkin.
  if ((status.isPermanentlyDenied || status.isRestricted) && context.mounted) {
    final open = await showConfirmDialog(
      context,
      title: title,
      message: tr(
        "Ruxsat avval rad etilgan. Uni telefon sozlamalaridan yoqing.",
      ),
      confirmLabel: tr('Sozlamalarni ochish'),
    );
    if (open) await openAppSettings();
  }
  return false;
}

/// Kunduzgi / Tungi rejim almashtirgich.
///
/// [compact] — AppBar uchun: quyosh/oy belgili dumaloq tugma.
/// To'liq variant — "Kunduzgi | Tungi" segmentli tugma.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppThemeController.instance,
      builder: (context, isDark, _) {
        void set(bool dark) => AppThemeController.instance.setDark(dark);

        if (compact) {
          return Tooltip(
            message: isDark ? tr('Kunduzgi rejim') : tr('Tungi rejim'),
            child: Material(
              color: AppColors.surfaceMuted,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => set(!isDark),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, anim) => RotationTransition(
                      turns: Tween(begin: 0.75, end: 1.0).animate(anim),
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Icon(
                      isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                      key: ValueKey(isDark),
                      size: 19,
                      color: isDark ? const Color(0xFFFBBF24) : AppColors.warning,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        const h = 40.0;
        Widget seg(bool dark, IconData icon, String label) {
          final selected = isDark == dark;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => set(dark),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(h / 2),
                  boxShadow: selected ? AppShadows.card : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 17,
                      color: selected ? AppColors.primary : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected ? AppColors.primary : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Container(
          height: h,
          width: 220,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(h / 2),
          ),
          child: Row(
            children: [
              seg(false, Icons.light_mode_rounded, tr('Kunduzgi')),
              seg(true, Icons.dark_mode_rounded, tr('Tungi')),
            ],
          ),
        );
      },
    );
  }
}
