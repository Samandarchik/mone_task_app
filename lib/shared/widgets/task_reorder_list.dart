import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mone_task_app/shared/models/task_model.dart';

/// Qadalgan vazifalar tepada — tartibning qolgan qismi saqlanadi.
List<TaskModel> pinnedFirst(List<TaskModel> tasks) => [
  ...tasks.where((t) => t.pinned),
  ...tasks.where((t) => !t.pinned),
];

/// Telegram'dagidek: qadalgan element faqat qadalganlar orasida,
/// qolganlari faqat o'zaro joy almashadi. [visible] dagi yangi tartibni qaytaradi.
/// Bosh sahifa (vazifalar) va «Все задачи» (shablonlar) uchun umumiy.
List<T> reorderedPinnedAware<T>(
  List<T> visible,
  int oldIndex,
  int newIndex,
  bool Function(T item) isPinned,
) {
  final list = [...visible];
  final moved = list.removeAt(oldIndex);
  final pinnedCount = list.where(isPinned).length;
  final target = isPinned(moved)
      ? newIndex.clamp(0, pinnedCount)
      : newIndex.clamp(pinnedCount, list.length);
  list.insert(target, moved);
  return list;
}

List<TaskModel> reorderedTasks(
  List<TaskModel> visible,
  int oldIndex,
  int newIndex,
) => reorderedPinnedAware(visible, oldIndex, newIndex, (t) => t.pinned);

/// [visible] ro'yxatidagi yangi tartibni umumiy [all] ro'yxatga joylaydi
/// (boshqa filial / filtrdan tashqaridagi elementlar o'z joyida qoladi).
List<T> mergeOrderBy<T, K>(
  List<T> all,
  List<T> visible,
  K Function(T item) key,
) {
  final ids = {for (final t in visible) key(t)};
  var k = 0;
  return [for (final t in all) ids.contains(key(t)) ? visible[k++] : t];
}

List<TaskModel> mergeOrder(List<TaskModel> all, List<TaskModel> visible) =>
    mergeOrderBy(all, visible, (t) => t.taskId);

/// Sudralayotgan karta — biroz kattalashib, soya bilan "ko'tariladi".
Widget liftedTaskProxy(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final t = Curves.easeOut.transform(animation.value);
      return Transform.scale(
        scale: lerpDouble(1, 1.03, t)!,
        child: Material(
          color: Colors.transparent,
          elevation: lerpDouble(0, 10, t)!,
          shadowColor: Colors.black38,
          borderRadius: BorderRadius.circular(18),
          child: child,
        ),
      );
    },
    child: child,
  );
}

/// Karta ko'tarilganda telefon titraydi
void reorderHaptic(int _) => HapticFeedback.mediumImpact();
