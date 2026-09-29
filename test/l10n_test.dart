import 'package:flutter_test/flutter_test.dart';
import 'package:mone_task_app/core/l10n/spelling_fixes.dart';
import 'package:mone_task_app/core/l10n/transliterator.dart';

void main() {
  test('latin -> cyrillic', () {
    expect(latinToCyrillic("O'chirish"), 'Ўчириш');
    expect(latinToCyrillic("Yo'q"), 'Йўқ');
    expect(latinToCyrillic("Ma'lumotlar yuklanmoqda"), 'Маълумотлар юкланмоқда');
    expect(latinToCyrillic('Ertalab eshikni yopish'), 'Эрталаб эшикни ёпиш');
    expect(latinToCyrillic('Chiqish'), 'Чиқиш');
    expect(latinToCyrillic("G'alaba SHAHAR"), 'Ғалаба ШАҲАР');
    expect(latinToCyrillic('Yangi vazifa'), 'Янги вазифа');
    expect(latinToCyrillic('Kategoriya'), 'Категория');
    expect(latinToCyrillic('MONE TASK'), 'MONE TASK');
    expect(latinToCyrillic('Yetkazish'), 'Етказиш');
  });
  test('cyrillic -> latin', () {
    expect(cyrillicToLatin('Ўчириш'), 'Oʻchirish');
    expect(cyrillicToLatin('Сибирский'), 'Sibirskiy');
    expect(cyrillicToLatin('Эрталаб ешик'), 'Ertalab yeshik');
    expect(cyrillicToLatin('Маълумот'), 'Maʼlumot');
    expect(cyrillicToLatin('ШАҲАР Шаҳар'), 'SHAHAR Shahar');
    expect(cyrillicToLatin('Қўнғироқ'), 'Qoʻngʻiroq');
  });
  test('apostrophes', () {
    expect(normalizeLatinApostrophes("O'chirish ma'lumot 'x'"), "Oʻchirish maʼlumot 'x'");
  });
  test('spelling', () {
    expect(fixCyrillicSpelling('Ишчиларни келмаганини аниклаш ва штраф килиш'),
        'Ишчиларни келмаганини аниқлаш ва штраф қилиш');
    expect(fixCyrillicSpelling('Хоз тавар ва напиткаларни руйхат билан текшириш ва тулдириш'),
        'Хозтовар ва напиткаларни рўйхат билан текшириш ва тўлдириш');
    expect(fixCyrillicSpelling('Ерталаб янги билинчикларни келишини хал килиш'),
        'Эрталаб янги блинчикларни келишини ҳал қилиш');
    expect(fixCyrillicSpelling('Опши дворни тоззалатиш ва 6 булимни яхшиллаб шпириб тоззалаш'),
        'Общий дворни тозалатиш ва 6 бўлимни яхшилаб супуриб тозалаш');
  });
}
