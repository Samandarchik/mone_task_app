/// Serverdan keladigan o'zbek kirill matnlaridagi (vazifalar, kategoriyalar)
/// tipik imlo xatolarini tuzatadi. Ma'no o'zgarmaydi — faqat harflar:
/// к→қ, г→ғ, у→ў, х→ҳ, е→э, tushib qolgan ъ va h.k.
///
/// Faqat kirill matnga qo'llanadi. Tuzatish so'z darajasida: avval aniq
/// so'zlar, keyin so'z o'zagi (qo'shimchalar saqlanadi).
library;

/// Butun ibora bo'yicha tuzatishlar (kichik harfda).
const Map<String, String> _phraseFixes = {
  'хоз тавар': 'хозтовар',
  'чёрнова света': 'чёрного цвета',
  'микра фибро': 'микрофибра',
  'опши двор': 'общий двор',
  'кафе даги': 'кафедаги',
};

/// Aniq so'z bo'yicha tuzatishlar (kichik harfda).
const Map<String, String> _wordFixes = {
  'хал': 'ҳал',
  'хар': 'ҳар',
  'узи': 'ўзи',
  'уз': 'ўз',
  'сунг': 'сўнг',
  'йок': 'йўқ',
  'йук': 'йўқ',
  'куп': 'кўп',
  'кура': 'кўра',
  'урни': 'ўрни',
  'хакида': 'ҳақида',
  'гел': 'гель',
  'мебел': 'мебель',
  'филял': 'филиал',
  'бронн': 'брон',
  'тавар': 'товар',
  'опши': 'общий',
  'сроги': 'сроки',
  'списани': 'списание',
  'марожни': 'мороженое',
  'писочни': 'песочное',
  'печенилар': 'печеньелар',
  'пирожнилар': 'пирожныйлар',
  'шпириб': 'супуриб',
  'шпириш': 'супуриш',
  'тулантириш': 'тўлатиш',
  'тулантириб': 'тўлатиб',
  'ёкиш': 'ёқиш',
  'ёкиб': 'ёқиб',
  'боллерга': 'бойлерга',
  'микра': 'микро',
  'фибро': 'фибра',
  'оркага': 'орқага',
  'давлени': 'давление',
  'нма': 'нима',
  'килб': 'қилиб',
  'хамисини': 'ҳаммасини',
  'ески': 'эски',
  'сех': 'цех',
  'махсулотларин': 'маҳсулотларини',
};

/// So'z o'zagi bo'yicha tuzatishlar: so'z shu o'zak bilan boshlansa,
/// o'zak almashtiriladi, qo'shimcha saqlanadi. Uzunroq o'zak ustun.
const Map<String, String> _stemFixes = {
  // қ
  'аниглаштир': 'аниқлаштир',
  'аникла': 'аниқла',
  'аниглаш': 'аниқлаш',
  'килдир': 'қилдир',
  'килин': 'қилин',
  'килиш': 'қилиш',
  'килиб': 'қилиб',
  'килган': 'қилган',
  'килма': 'қилма',
  'килди': 'қилди',
  'килса': 'қилса',
  'кила': 'қила',
  'кайна': 'қайна',
  'кечкурун': 'кечқурун',
  'чикар': 'чиқар',
  'чикиш': 'чиқиш',
  'чикиб': 'чиқиб',
  'чикган': 'чиқган',
  'окшом': 'оқшом',
  'овкат': 'овқат',
  'дакика': 'дақиқа',
  'бошка': 'бошқа',
  'кабул': 'қабул',
  'йокиш': 'ёқиш',
  'йокиб': 'ёқиб',
  'йокил': 'ёқил',
  'ёкил': 'ёқил',
  'тулик': 'тўлиқ',
  // ғ
  'йигил': 'йиғил',
  'йигиш': 'йиғиш',
  'йигиб': 'йиғиб',
  'ёгини': 'ёғини',
  'ёги': 'ёғи',
  'тугри': 'тўғри',
  'кунгирок': 'қўнғироқ',
  // ў
  'тулдир': 'тўлдир',
  'тулалиг': 'тўлалиг',
  'булим': 'бўлим',
  'руйхат': 'рўйхат',
  'утказ': 'ўтказ',
  'утган': 'ўтган',
  'сураш': 'сўраш',
  'сураб': 'сўраб',
  'куйиш': 'қўйиш',
  'куйил': 'қўйил',
  'куйиб': 'қўйиб',
  'куйинг': 'қўйинг',
  'куриб': 'кўриб',
  'куриш': 'кўриш',
  'курсат': 'кўрсат',
  'кучалар': 'кўчалар',
  'узгар': 'ўзгар',
  'кушиш': 'қўшиш',
  'кушиб': 'қўшиб',
  // ҳ
  'хамма': 'ҳамма',
  'хафта': 'ҳафта',
  'хисоб': 'ҳисоб',
  'холат': 'ҳолат',
  'хосил': 'ҳосил',
  'хожатхоналр': 'ҳожатхоналар',
  'хожатхона': 'ҳожатхона',
  'махсулот': 'маҳсулот',
  // ъ
  'малумот': 'маълумот',
  // э
  'ерталаб': 'эрталаб',
  'ешик': 'эшик',
  // ёзиш
  'йозиш': 'ёзиш',
  'йозиб': 'ёзиб',
  // Qo'sh / ortiqcha harflar
  'тоззал': 'тозал',
  'таёргарлик': 'тайёргарлик',
  'сехни': 'цехни',
  'сехда': 'цехда',
  'сехга': 'цехга',
  'срогда': 'срокда',
  'срогига': 'срокига',
  'ескиси': 'эскиси',
  'йукл': 'йўқл',
  'яхшилла': 'яхшила',
  'бланкалр': 'бланкалар',
  // Ruscha so'zlarning to'g'ri yozilishi
  'поворлар': 'поварлар',
  'повор': 'повар',
  'билинчик': 'блинчик',
  'отзыф': 'отзыв',
  'пасуда': 'посуда',
  'катёл': 'котёл',
  'камомат': 'камомад',
  'витишка': 'вытяжка',
  'дивижок': 'движок',
  'даводчик': 'доводчик',
  'мусхона': 'музхона',
  'зубачистка': 'зубочистка',
  'калонка': 'колонка',
  'музика': 'мусиқа',
  'тилвизор': 'телевизор',
  'кондитсионер': 'кондиционер',
  'халаделник': 'холодильник',
  'халаделниг': 'холодильниг',
  'давленис': 'давлениес',
  'офицант': 'официант',
  'терасса': 'терраса',
  'колган': 'қолган',
  'колди': 'қолди',
  'колдир': 'қолдир',
  'кулай': 'қулай',
  'куллан': 'қўллан',
  'кулланма': 'қўлланма',
  'кутиларни': 'қутиларни',
  'ховли': 'ҳовли',
  'хужжат': 'ҳужжат',
  'хисобот': 'ҳисобот',
  'урнат': 'ўрнат',
  'узгартир': 'ўзгартир',
  'угир': 'ўгир',
  'укит': 'ўқит',
  'укиш': 'ўқиш',
  'кушимча': 'қўшимча',
  'киммат': 'қиммат',
  'кисм': 'қисм',
  'йигишти': 'йиғишти',
  'тухта': 'тўхта',
  'тупла': 'тўпла',
  'совутгич': 'совуткич',
};

final List<MapEntry<String, String>> _stemsByLength =
    _stemFixes.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

final RegExp _cyrWordRe = RegExp(r'[А-Яа-яЁёЎўҚқҒғҲҳ]+');

String _matchCase(String source, String fixed) {
  if (source.length > 1 && source == source.toUpperCase()) {
    return fixed.toUpperCase();
  }
  if (source.isNotEmpty && source[0] != source[0].toLowerCase()) {
    return fixed[0].toUpperCase() + fixed.substring(1);
  }
  return fixed;
}

String _fixWord(String word) {
  final lower = word.toLowerCase();
  final exact = _wordFixes[lower];
  if (exact != null) return _matchCase(word, exact);
  for (final e in _stemsByLength) {
    if (lower.startsWith(e.key) && !lower.startsWith(e.value)) {
      return _matchCase(word, e.value + lower.substring(e.key.length));
    }
  }
  return word;
}

/// Kirill matnidagi imlo xatolarini tuzatadi. Lotin matnga tegmaydi.
String fixCyrillicSpelling(String input) {
  var text = input;
  // Iboralar (katta-kichik harfga qaramay)
  _phraseFixes.forEach((wrong, right) {
    text = text.replaceAllMapped(
      RegExp(RegExp.escape(wrong), caseSensitive: false, unicode: true),
      (m) => _matchCase(m.group(0)!, right),
    );
  });
  text = text.replaceAllMapped(_cyrWordRe, (m) => _fixWord(m.group(0)!));
  // Ortiqcha bo'shliqlar: "ва  текшириш" → "ва текшириш"
  text = text.replaceAll(RegExp(r'\s*\n\s*'), ' ');
  text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  text = text.replaceAllMapped(RegExp(r' +([,.:;!?)])'), (m) => m.group(1)!);
  text = text.replaceAll(RegExp(r'\( +'), '(');
  return text.trim();
}
