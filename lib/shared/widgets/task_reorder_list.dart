import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mone_task_app/shared/models/task_model.dart';

/// Telegram'dagidek: [visible] ro'yxatda elementni [oldIndex] dan [newIndex]
/// ga ko'chiradi. Bosh sahifa (vazifalar) va «Все задачи» (shablonlar) uchun umumiy.
List<T> reordered<T>(List<T> visible, int oldIndex, int newIndex) {
  final list = [...visible];
  final moved = list.removeAt(oldIndex);
  list.insert(newIndex.clamp(0, list.length), moved);
  return list;
}

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
