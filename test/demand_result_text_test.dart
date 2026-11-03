import 'package:flutter_test/flutter_test.dart';
import 'package:mone_task_app/shared/widgets/task_reminders.dart';

void main() {
  test('mas\'ul yo\'q bo\'lsa «Потребовано» demaydi', () {
    expect(
      demandResultText({'responsible': []}),
      'Нет ответственных — некому отправить',
    );
  });

  test('hammaga yetgan', () {
    expect(
      demandResultText({
        'responsible': [{}, {}],
        'online': 1,
        'push': 2,
        'telegram': 1,
        'notReached': [],
      }),
      'Потребовано. В приложении: 1, уведомление: 2',
    );
  });

  test('yetmaganlar ko\'rsatiladi', () {
    expect(
      demandResultText({
        'responsible': [{}, {}, {}],
        'online': 0,
        'push': 1,
        'telegram': 0,
        'notReached': ['Ali', 'Vali'],
      }),
      'Потребовано. В приложении: 0, уведомление: 1\n'
      'Не доставлено: Ali, Vali',
    );
  });

  test('eski server javobi (push yo\'q) ham ishlaydi', () {
    expect(
      demandResultText({
        'responsible': [{}],
        'online': 1,
        'telegram': 1,
      }),
      'Потребовано. В приложении: 1, уведомление: 0',
    );
  });
}
