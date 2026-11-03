import 'package:flutter_test/flutter_test.dart';
import 'package:mone_task_app/shared/models/task_model.dart';
import 'package:mone_task_app/worker/ui/task_worker_ui.dart';

TaskModel task(int id, int filialId, String category) => TaskModel(
  taskId: id,
  task: 'Vazifa $id',
  type: 1,
  filialId: filialId,
  category: category,
);

void main() {
  final tasks = [
    task(1, 10, 'Кечкурунгги Админ'),
    // Kategoriyasiz — server hammaga beradi, ishchida ham ko'rinishi shart
    task(2, 10, ''),
    task(3, 20, ''),
    task(4, 20, 'Эрталабги Админ'),
  ];

  test('kategoriyasiz vazifa yashirinmaydi', () {
    expect(workerVisibleTasks(tasks, null).map((t) => t.taskId), [1, 2, 3, 4]);
  });

  test('aktiv filial bo\'yicha ajratiladi', () {
    expect(workerVisibleTasks(tasks, 10).map((t) => t.taskId), [1, 2]);
    expect(workerVisibleTasks(tasks, 20).map((t) => t.taskId), [3, 4]);
  });

  test('muddat ko\'rinishi', () {
    expect(taskDeadline('12:00'), '12:00');
    expect(taskDeadline('5:0'), '05:00');
    expect(taskDeadline('null:null'), isNull);
    expect(taskDeadline(null), isNull);
    expect(taskDeadline('25:00'), isNull);
  });
}
