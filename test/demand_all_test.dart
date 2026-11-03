import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/shared/widgets/task_reminders.dart';

/// Jonli server o'rniga: overdue ro'yxati va talab so'rovlarini yozib boradi
class _FakeServer extends Interceptor {
  final demanded = <String>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.uri.path;
    if (options.method == 'GET' && path.endsWith('/tasks/overdue')) {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'data': [
              _task(1, 'Pol yuvish', ['Ali']),
              _task(2, 'Svet', ['Vali']),
              _task(3, 'Mas\'ulsiz', []),
            ],
          },
        ),
      );
      return;
    }
    if (options.method == 'POST' && path.endsWith('/demand')) {
      demanded.add(path);
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'success': true,
            'responsible': [{}],
            'online': 0,
            'push': 0,
            'notReached': path.contains('/2/') ? ['Vali'] : [],
          },
        ),
      );
      return;
    }
    handler.reject(DioException(requestOptions: options));
  }

  static Map<String, dynamic> _task(int id, String name, List<String> who) => {
    'taskId': id,
    'filialName': 'Фреско',
    'task': name,
    'time': '12:00',
    'lateMinutes': 30,
    'responsible': [
      for (final w in who) {'username': w},
    ],
  };
}

void main() {
  late _FakeServer server;

  setUp(() {
    server = _FakeServer();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..interceptors.add(server);
    if (sl.isRegistered<Dio>()) sl.unregister<Dio>();
    sl.registerSingleton<Dio>(dio);
  });

  testWidgets('«Потребовать у всех» — tasdiqdan keyin har bir mas\'ulli '
      'vazifaga bitta talab', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: OverdueBellButton(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    // Mas'ulsiz vazifa hisobga kirmaydi
    expect(find.text('Потребовать у всех (2)'), findsOneWidget);

    await tester.tap(find.text('Потребовать у всех (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Потребовать у всех?'), findsOneWidget);

    // Bekor qilinsa — hech narsa yuborilmaydi
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(server.demanded, isEmpty);

    await tester.tap(find.text('Потребовать у всех (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Потребовать'));
    await tester.pumpAndSettle();

    expect(server.demanded.toSet(), {
      '/api/tasks/1/demand',
      '/api/tasks/2/demand',
    });
    expect(find.textContaining('Потребовано: 2 из 2'), findsOneWidget);
    expect(find.textContaining('Не доставлено: Vali'), findsOneWidget);
  });
}
