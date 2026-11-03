import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mone_task_app/shared/widgets/task_card_header.dart';

void main() {
  final longText = 'Длинный текст задачи для проверки ' * 10;

  Future<void> pump(WidgetTester tester, double width, String text) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Builder(
              builder: (context) => TaskCardHeader(
                leading: const SizedBox(width: 26, height: 26),
                title: Text(
                  text,
                  key: const Key('title'),
                  style: TextStyle(
                    fontSize: taskTitleFontSize(context, text, wide: 18),
                  ),
                ),
                // Admin kartasidagi ▶ va 3 ta status doirasi kengligi
                actions: const [SizedBox(width: 138, height: 28)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double fontSize(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('title'))).style!.fontSize!;

  double titleWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(const Key('title'))).width;

  for (final width in [320.0, 360.0, 412.0]) {
    testWidgets('telefon ${width}dp: matn to\'liq kenglikda', (tester) async {
      await pump(tester, width, longText);
      expect(tester.takeException(), isNull);
      expect(titleWidth(tester), width - 48);
    });
  }

  testWidgets('katta ekran: matn tugmalar bilan bir qatorda', (tester) async {
    await pump(tester, 800, longText);
    expect(tester.takeException(), isNull);
    expect(titleWidth(tester), 800 - 48 - 26 - 10 - 138);
    expect(fontSize(tester), 18);
  });

  testWidgets('shrift matn uzunligi va ekranga qarab kichrayadi', (
    tester,
  ) async {
    await pump(tester, 360, 'Короткий');
    expect(fontSize(tester), 15.5);
    await pump(tester, 360, 'а' * 100);
    expect(fontSize(tester), 14.5);
    await pump(tester, 360, 'а' * 200);
    expect(fontSize(tester), 13.5);
    await pump(tester, 320, 'а' * 200);
    expect(fontSize(tester), 13);
  });
}
