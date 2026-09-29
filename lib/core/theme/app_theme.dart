import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dizayn tizimi — ranglar, oraliqlar, radiuslar va umumiy tema.
/// Barcha ekranlar shu qiymatlardan foydalanadi (qo'lda rang yozilmaydi).
/// Rang palitrasi (kunduzgi / tungi).
class AppPalette {
  const AppPalette({
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
  });

  final Color primary;
  final Color primaryDark;
  final Color primarySoft;
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  static const light = AppPalette(
    primary: Color(0xFF2F6BFF),
    primaryDark: Color(0xFF1F4FD1),
    primarySoft: Color(0xFFEAF0FF),
    background: Color(0xFFF5F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1F3F7),
    border: Color(0xFFE4E7EE),
    divider: Color(0xFFEDEFF3),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF5B6475),
    textTertiary: Color(0xFF9AA1AE),
    success: Color(0xFF16A34A),
    successSoft: Color(0xFFE7F7ED),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFFFFF4E0),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0xFFFDECEC),
    info: Color(0xFF0EA5E9),
    infoSoft: Color(0xFFE6F6FD),
  );

  static const dark = AppPalette(
    primary: Color(0xFF5B8CFF),
    primaryDark: Color(0xFFB4C8FF),
    primarySoft: Color(0xFF1B2A4D),
    background: Color(0xFF0D1016),
    surface: Color(0xFF161A23),
    surfaceMuted: Color(0xFF212734),
    border: Color(0xFF2B3240),
    divider: Color(0xFF222835),
    textPrimary: Color(0xFFE9ECF2),
    textSecondary: Color(0xFFA4ABB9),
    textTertiary: Color(0xFF6F7788),
    success: Color(0xFF34D399),
    successSoft: Color(0xFF10301F),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0xFF3A2D0C),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0xFF3A1717),
    info: Color(0xFF38BDF8),
    infoSoft: Color(0xFF0E2B3A),
  );
}

/// Kunduzgi / tungi rejim. O'zgarganda butun ilova darhol qayta chiziladi.
class AppThemeController extends ValueNotifier<bool> {
  AppThemeController._() : super(false);

  static final AppThemeController instance = AppThemeController._();
  static const String _key = 'app_dark_mode_v1';

  bool get isDark => value;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = prefs.getBool(_key) ?? false;
  }

  Future<void> setDark(bool dark) async {
    if (value == dark) return;
    value = dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, dark);
  }
}

/// Joriy rejim ranglari. `AppColors.primary` kabi ishlatiladi.
abstract final class AppColors {
  static AppPalette get _p =>
      AppThemeController.instance.value ? AppPalette.dark : AppPalette.light;

  static Color get primary => _p.primary;
  static Color get primaryDark => _p.primaryDark;
  static Color get primarySoft => _p.primarySoft;
  static Color get background => _p.background;
  static Color get surface => _p.surface;
  static Color get surfaceMuted => _p.surfaceMuted;
  static Color get border => _p.border;
  static Color get divider => _p.divider;
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textTertiary => _p.textTertiary;
  static Color get success => _p.success;
  static Color get successSoft => _p.successSoft;
  static Color get warning => _p.warning;
  static Color get warningSoft => _p.warningSoft;
  static Color get danger => _p.danger;
  static Color get dangerSoft => _p.dangerSoft;
  static Color get info => _p.info;
  static Color get infoSoft => _p.infoSoft;
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Ekran chetlaridan standart ichki oraliq.
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: 16);
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  static final BorderRadius smAll = BorderRadius.circular(sm);
  static final BorderRadius mdAll = BorderRadius.circular(md);
  static final BorderRadius lgAll = BorderRadius.circular(lg);
  static final BorderRadius xlAll = BorderRadius.circular(xl);
}

abstract final class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F111827), blurRadius: 12, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x1A111827), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

/// Vazifa holati → rang (1 = bajarilmagan, 2 = tekshiruvda, 3 = bajarilgan).
Color statusColor(int status) => switch (status) {
  3 => AppColors.success,
  2 => AppColors.warning,
  _ => AppColors.danger,
};

Color statusSoftColor(int status) => switch (status) {
  3 => AppColors.successSoft,
  2 => AppColors.warningSoft,
  _ => AppColors.dangerSoft,
};

abstract final class AppTheme {
  /// Joriy rejim (kunduzgi / tungi) uchun tema.
  static ThemeData current() {
    final isDark = AppThemeController.instance.isDark;
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          primaryContainer: AppColors.primarySoft,
          onPrimaryContainer: AppColors.primaryDark,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          onSurfaceVariant: AppColors.textSecondary,
          surfaceContainerHighest: AppColors.surfaceMuted,
          outline: AppColors.border,
          outlineVariant: AppColors.divider,
          error: AppColors.danger,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    final text = base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    final textTheme = text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: text.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, height: 1.4),
      bodySmall: text.bodySmall?.copyWith(
        fontSize: 12.5,
        color: AppColors.textSecondary,
        height: 1.35,
      ),
      labelLarge: text.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide: BorderSide(color: AppColors.border),
    );

    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
    );
    const buttonSize = Size(64, 50);
    final buttonText = textTheme.labelLarge;

    return base.copyWith(
      textTheme: textTheme,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SmoothPageTransitionsBuilder(),
          TargetPlatform.windows: SmoothPageTransitionsBuilder(),
          TargetPlatform.linux: SmoothPageTransitionsBuilder(),
          TargetPlatform.macOS: SmoothPageTransitionsBuilder(),
          // iOS: tizimning o'z (orqaga surish bilan) animatsiyasi
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: AppColors.border,
        centerTitle: false,
        titleSpacing: 16,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: AppColors.textTertiary),
        labelStyle: TextStyle(color: AppColors.textSecondary),
        floatingLabelStyle: TextStyle(color: AppColors.primary),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: buttonSize,
          shape: buttonShape,
          side: BorderSide(color: AppColors.border),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        // Tanlangan bo'lim kattaroq va qalinroq — o'tishda silliq kattalashadi
        labelStyle: textTheme.titleSmall?.copyWith(
          fontSize: 17.5,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: textTheme.titleSmall?.copyWith(
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
        ),
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        // Tanlangan tab orqasida yumshoq "pill" + pastki chiziq
        indicator: ShapeDecoration(
          color: AppColors.primarySoft,
          shape: StadiumBorder(
            side: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
        ),
        indicatorAnimation: TabIndicatorAnimation.elastic,
        splashBorderRadius: BorderRadius.circular(999),
        dividerColor: AppColors.divider,
        tabAlignment: TabAlignment.start,
        labelPadding: EdgeInsets.symmetric(horizontal: 16),
        overlayColor: WidgetStateProperty.all(AppColors.primarySoft),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primarySoft,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: s.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceMuted,
        // Tanlangan chip to'liq rangli — qaysi bo'limda ekanligi aniq bilinsin
        selectedColor: AppColors.primary,
        secondaryLabelStyle: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        checkmarkColor: Colors.white,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        labelStyle: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        titleTextStyle: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        subtitleTextStyle: textTheme.bodySmall,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? Color(0xFF2A3140) : AppColors.textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        insetPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.primarySoft,
          selectedForegroundColor: AppColors.primaryDark,
          side: BorderSide(color: AppColors.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
    );
  }
}

/// Sahifalar almashinuvi: o'rtacha tezlik (380 ms), yumshoq —
/// yangi sahifa o'ngdan biroz siljib, asta paydo bo'ladi.
class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Duration(milliseconds: 380);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const curve = Curves.easeOutCubic;
    final inAnim = CurvedAnimation(
      parent: animation,
      curve: curve,
      reverseCurve: Curves.easeInCubic,
    );
    final outAnim = CurvedAnimation(parent: secondaryAnimation, curve: curve);

    return SlideTransition(
      position: Tween(begin: Offset.zero, end: Offset(-0.08, 0))
          .animate(outAnim),
      child: SlideTransition(
        position: Tween(begin: Offset(0.18, 0), end: Offset.zero)
            .animate(inAnim),
        child: FadeTransition(
          opacity: Tween<double>(begin: 0, end: 1).animate(
            CurvedAnimation(
              parent: animation,
              curve: Interval(0, 0.7, curve: Curves.easeOut),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
