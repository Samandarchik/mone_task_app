/// O'zbek lotin ⇄ kirill transliteratsiyasi (1995-yilgi rasmiy qoidalar
/// asosida). Rus tilidagi so'zlar (щ, ы, ь, ц ...) ham to'g'ri o'giriladi.
///
/// Lotin yozuvida rasmiy belgilar ishlatiladi:
///   oʻ / gʻ  — U+02BB (ʻ)
///   tutuq    — U+02BC (ʼ)
library;

const String kOkina = 'ʻ'; // U+02BB — oʻ, gʻ
const String kTutuq = 'ʼ'; // U+02BC — maʼlumot

/// Klaviaturadagi turli apostroflar bitta ko'rinishga keltiriladi.
const Set<String> _apostrophes = {"'", '`', '‘', '’', 'ʻ', 'ʼ', '´'};

bool _isApos(String ch) => _apostrophes.contains(ch);

bool _isUpper(String ch) => ch != ch.toLowerCase() && ch == ch.toUpperCase();

bool _isLetter(String ch) => ch.toLowerCase() != ch.toUpperCase();

final RegExp _cyrillicRe = RegExp(r'[А-Яа-яЁёЎўҚқҒғҲҳ]');
final RegExp _latinRe = RegExp(r'[A-Za-z]');

bool hasCyrillic(String s) => _cyrillicRe.hasMatch(s);
bool hasLatin(String s) => _latinRe.hasMatch(s);

// ─────────────────────────────────────────────────────────────────────────
// Kirill → Lotin
// ─────────────────────────────────────────────────────────────────────────

const Map<String, String> _c2l = {
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'ж': 'j',
  'з': 'z',
  'и': 'i',
  'й': 'y',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'x',
  'ц': 'ts',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'sh',
  'ъ': kTutuq,
  'ы': 'i',
  'ь': '',
  'э': 'e',
  'ю': 'yu',
  'я': 'ya',
  'ё': 'yo',
  'ў': 'o$kOkina',
  'қ': 'q',
  'ғ': 'g$kOkina',
  'ҳ': 'h',
};

const String _cyrVowels = 'аеёиоуэюяўы';

String cyrillicToLatin(String input) {
  if (!hasCyrillic(input)) return input;
  final chars = input.split('');
  final out = StringBuffer();
  for (var i = 0; i < chars.length; i++) {
    final ch = chars[i];
    final lower = ch.toLowerCase();
    String? lat;
    if (lower == 'е') {
      // So'z boshida yoki unli / ъ / ь dan keyin — "ye", aks holda "e".
      final prev = i > 0 ? chars[i - 1].toLowerCase() : '';
      final atStart = i == 0 || !_isLetter(prev);
      lat = (atStart || _cyrVowels.contains(prev) || prev == 'ъ' || prev == 'ь')
          ? 'ye'
          : 'e';
    } else {
      lat = _c2l[lower];
    }
    if (lat == null) {
      out.write(ch);
      continue;
    }
    if (_isUpper(ch) && lat.isNotEmpty) {
      // Keyingi harf ham katta bo'lsa (SHAHAR) — to'liq katta; aks holda Sh.
      final next = i + 1 < chars.length ? chars[i + 1] : '';
      final prev = i > 0 ? chars[i - 1] : '';
      final allCaps =
          (_isLetter(next) && _isUpper(next)) ||
          (!_isLetter(next) && _isLetter(prev) && _isUpper(prev));
      lat = allCaps
          ? lat.toUpperCase()
          : lat[0].toUpperCase() + lat.substring(1);
    }
    out.write(lat);
  }
  return out.toString();
}

// ─────────────────────────────────────────────────────────────────────────
// Lotin → Kirill
// ─────────────────────────────────────────────────────────────────────────

const Map<String, String> _l2c = {
  'a': 'а',
  'b': 'б',
  'c': 'ц',
  'd': 'д',
  'f': 'ф',
  'g': 'г',
  'h': 'ҳ',
  'i': 'и',
  'j': 'ж',
  'k': 'к',
  'l': 'л',
  'm': 'м',
  'n': 'н',
  'o': 'о',
  'p': 'п',
  'q': 'қ',
  'r': 'р',
  's': 'с',
  't': 'т',
  'u': 'у',
  'v': 'в',
  'w': 'в',
  'x': 'х',
  'y': 'й',
  'z': 'з',
};

const String _latVowels = 'aeiouAEIOU';

/// Kirill yozuvida ruscha shaklda yoziladigan so'zlar (ь, ц, я ...).
/// Kalit — lotin (kichik harf), qiymat — kirill (kichik harf).
const Map<String, String> _l2cExceptions = {
  'yanvar': 'январь',
  'fevral': 'февраль',
  'aprel': 'апрель',
  'iyun': 'июнь',
  'iyul': 'июль',
  'sentabr': 'сентябрь',
  'oktabr': 'октябрь',
  'noyabr': 'ноябрь',
  'dekabr': 'декабрь',
  'kompyuter': 'компьютер',
  'rol': 'роль',
  'rollar': 'роллар',
  'rolni': 'ролни',
  'rolini': 'ролини',
  'rolga': 'ролга',
  'funksiya': 'функция',
  'litsenziya': 'лицензия',
  'konditsioner': 'кондиционер',
  'mebel': 'мебель',
  'voditel': 'водитель',
  'voditellar': 'водителлар',
};

/// Transliteratsiya qilinmaydigan so'zlar (brend, texnik nomlar).
const Set<String> _l2cKeep = {
  'mone',
  'task',
  'excel',
  'xlsx',
  'pdf',
  'ok',
  'id',
  'vpn',
  'wi',
  'fi',
  'http',
  'https',
  'www',
  'url',
};

final RegExp _latWordRe = RegExp(r"[A-Za-z][A-Za-z'`‘’ʻʼ´]*");

String latinToCyrillic(String input) {
  if (!hasLatin(input)) return input;
  // URL, email va @username larga tegmaymiz.
  final protectedRe = RegExp(r'(https?://\S+|\S+@\S+|@\w+)');
  final buf = StringBuffer();
  var last = 0;
  for (final m in protectedRe.allMatches(input)) {
    buf.write(_latinToCyrillicPlain(input.substring(last, m.start)));
    buf.write(m.group(0));
    last = m.end;
  }
  buf.write(_latinToCyrillicPlain(input.substring(last)));
  return buf.toString();
}

String _latinToCyrillicPlain(String input) {
  return input.replaceAllMapped(_latWordRe, (m) {
    final word = m.group(0)!;
    // So'z oxiridagi apostrof — tirnoq, so'zga tegishli emas.
    var core = word;
    var tail = '';
    while (core.isNotEmpty && _isApos(core[core.length - 1])) {
      final before = core.length >= 2
          ? core[core.length - 2].toLowerCase()
          : '';
      if (before == 'o' || before == 'g') break;
      tail = core[core.length - 1] + tail;
      core = core.substring(0, core.length - 1);
    }
    final lower = core.toLowerCase();
    if (_l2cKeep.contains(lower)) return word;
    final exc = _l2cExceptions[lower];
    if (exc != null) return _applyCase(core, exc) + tail;
    return _wordLatinToCyrillic(core) + tail;
  });
}

String _applyCase(String source, String target) {
  if (source.length > 1 && source == source.toUpperCase()) {
    return target.toUpperCase();
  }
  if (_isUpper(source[0])) {
    return target[0].toUpperCase() + target.substring(1);
  }
  return target;
}

String _wordLatinToCyrillic(String w) {
  final c = w.split('');
  final out = StringBuffer();
  var i = 0;
  final allCaps = w.length > 1 && w == w.toUpperCase();

  String cased(String cyr, String first) =>
      _isUpper(first) ? cyr.toUpperCase() : cyr;

  while (i < c.length) {
    final ch = c[i];
    final lo = ch.toLowerCase();
    final n1 = i + 1 < c.length ? c[i + 1] : '';
    final n1l = n1.toLowerCase();
    final n2 = i + 2 < c.length ? c[i + 2] : '';

    // oʻ, gʻ
    if ((lo == 'o' || lo == 'g') && _isApos(n1)) {
      out.write(cased(lo == 'o' ? 'ў' : 'ғ', ch));
      i += 2;
      continue;
    }
    // sh, ch
    if ((lo == 's' || lo == 'c') && n1l == 'h') {
      out.write(cased(lo == 's' ? 'ш' : 'ч', ch));
      i += 2;
      continue;
    }
    // ng — alohida harflar (н + г), maxsus qoida yo'q.
    // yo, yu, ya, ye — lekin "yoʻ" = й + ў
    if (lo == 'y' && 'ouae'.contains(n1l) && n1l.isNotEmpty) {
      if (n1l == 'o' && _isApos(n2)) {
        out.write(cased('й', ch));
        i += 1;
        continue;
      }
      final map = {'o': 'ё', 'u': 'ю', 'a': 'я', 'e': 'е'};
      final firstUpper = _isUpper(ch);
      out.write(firstUpper ? map[n1l]!.toUpperCase() : map[n1l]!);
      i += 2;
      continue;
    }
    if (lo == 'e') {
      final prev = i > 0 ? c[i - 1] : '';
      final atStart = i == 0;
      final afterVowel = prev.isNotEmpty && _latVowels.contains(prev);
      out.write(cased(atStart || afterVowel ? 'э' : 'е', ch));
      i += 1;
      continue;
    }
    if (_isApos(ch)) {
      // Tutuq belgisi → ъ
      out.write(allCaps ? 'Ъ' : 'ъ');
      i += 1;
      continue;
    }
    final cyr = _l2c[lo];
    if (cyr == null) {
      out.write(ch);
    } else {
      out.write(cased(cyr, ch));
    }
    i += 1;
  }
  final result = out.toString();
  return allCaps ? result.toUpperCase() : result;
}

/// Lotin matnidagi apostroflarni rasmiy belgilarga keltiradi:
/// o' → oʻ, g' → gʻ, boshqalari → ʼ (tutuq).
String normalizeLatinApostrophes(String input) {
  if (!hasLatin(input)) return input;
  final c = input.split('');
  for (var i = 0; i < c.length; i++) {
    if (!_isApos(c[i])) continue;
    final prev = i > 0 ? c[i - 1] : '';
    final next = i + 1 < c.length ? c[i + 1] : '';
    // Tirnoq sifatida ishlatilgan bo'lsa ('matn') — tegmaymiz.
    if (!_isLetter(prev) || !_isLetter(next) && !'oOgG'.contains(prev)) {
      continue;
    }
    final pl = prev.toLowerCase();
    c[i] = (pl == 'o' || pl == 'g') ? kOkina : kTutuq;
  }
  return c.join();
}
