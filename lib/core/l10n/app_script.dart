import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mone_task_app/core/l10n/spelling_fixes.dart';
import 'package:mone_task_app/core/l10n/transliterator.dart';

/// Ilova yozuvi: o'zbek lotin yoki o'zbek kirill.
enum AppScript { latin, cyrillic }

/// Tanlangan alifbo. O'zgarganda butun ilova darhol qayta chiziladi
/// (qarang: [ScriptScope]).
class AppScriptController extends ValueNotifier<AppScript> {
  AppScriptController._() : super(AppScript.latin);

  static final AppScriptController instance = AppScriptController._();

  static const String _key = 'app_script_v1';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = prefs.getString(_key) == 'cyrillic'
        ? AppScript.cyrillic
        : AppScript.latin;
  }

  Future<void> set(AppScript script) async {
    if (value == script) return;
    value = script;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, script.name);
  }

  void toggle() =>
      set(value == AppScript.latin ? AppScript.cyrillic : AppScript.latin);

  bool get isLatin => value == AppScript.latin;
}

AppScript get currentScript => AppScriptController.instance.value;

final Map<String, String> _cyrCache = {};

/// Ilova ichidagi (statik) matn. Doim **o'zbek lotin**da yoziladi:
/// `tr("Oʻchirish")`. Kirill tanlanganda avtomatik o'giriladi.
///
/// Transliteratsiya xato beradigan kamdan-kam holatlar uchun [cyr] bilan
/// kirill variantini qo'lda berish mumkin.
///
/// Muhim: `$e` kabi o'zgaruvchilarni tr() ichiga qo'ymang —
/// `"${tr('Xatolik')}: $e"` ko'rinishida yozing.
String tr(String latin, {String? cyr}) {
  if (currentScript == AppScript.latin) {
    return normalizeLatinApostrophes(latin);
  }
  if (cyr != null) return cyr;
  return _cyrCache.putIfAbsent(latin, () => latinToCyrillic(latin));
}

final Map<String, String> _dataCacheLat = {};
final Map<String, String> _dataCacheCyr = {};

/// Serverdan kelgan matn (vazifa, kategoriya, filial, ism).
/// Imlo xatolari tuzatiladi va tanlangan alifboga o'giriladi.
String trData(String? text) {
  if (text == null || text.isEmpty) return text ?? '';
  final latin = currentScript == AppScript.latin;
  final cache = latin ? _dataCacheLat : _dataCacheCyr;
  return cache.putIfAbsent(text, () {
    final fixed = hasCyrillic(text) ? fixCyrillicSpelling(text) : text;
    return latin
        ? normalizeLatinApostrophes(cyrillicToLatin(fixed))
        : latinToCyrillic(fixed);
  });
}

/// Nom (filial, kategoriya, foydalanuvchi): [trData] + bosh harf katta.
String displayName(String? name) {
  final t = trData(name?.trim());
  if (t.isEmpty) return t;
  return t[0].toUpperCase() + t.substring(1);
}

/// Butun ilova daraxtini alifbo o'zgarganda qayta quradi — hech bir
/// ekran holati (state) yo'qolmaydi, faqat matnlar yangilanadi.
class ScriptScope extends StatefulWidget {
  const ScriptScope({super.key, required this.child, this.extra = const []});

  final Widget child;

  /// Qo'shimcha manbalar (masalan, kunduzgi/tungi rejim) — ular o'zgarganda
  /// ham butun daraxt qayta chiziladi.
  final List<Listenable> extra;

  @override
  State<ScriptScope> createState() => _ScriptScopeState();
}

class _ScriptScopeState extends State<ScriptScope> {
  final _controller = AppScriptController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    for (final l in widget.extra) {
      l.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    for (final l in widget.extra) {
      l.removeListener(_onChanged);
    }
    super.dispose();
  }

  void _onChanged() {
    void rebuild(Element el) {
      el.markNeedsBuild();
      el.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
