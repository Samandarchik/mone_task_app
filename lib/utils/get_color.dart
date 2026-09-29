import 'package:flutter/material.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';

/// Vazifa holati rangi (1 — bajarilmagan, 2 — tekshiruvda, 3 — bajarilgan).
Color getStatusColor(int status) => statusColor(status);

/// Vazifa turi nomi.
String getTypeName(int type) {
  switch (type) {
    case 1:
      return tr('Har kuni');
    case 2:
      return '${tr('Har hafta')}: ';
    case 3:
      return '${tr('Har oy')}: ';
    default:
      return tr("Noma'lum");
  }
}

/// Hafta kuni qisqa nomi (1 — dushanba ... 7 — yakshanba).
String getWeekday(int date) {
  switch (date) {
    case 1:
      return tr('Du');
    case 2:
      return tr('Se');
    case 3:
      return tr('Ch');
    case 4:
      return tr('Pa');
    case 5:
      return tr('Ju');
    case 6:
      return tr('Sh');
    case 7:
      return tr('Ya');
    default:
      return '--';
  }
}

String getWeekdaysString(List<int>? days) {
  if (days == null || days.isEmpty) return "";
  return days.map((d) => getWeekday(d)).join(", ");
}
