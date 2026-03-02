import 'package:flutter/material.dart';

/// 🔥 STATUS COLOR
Icon getStatusColor(int status) {
  switch (status) {
    case 3:
      return Icon(Icons.check_circle, color: Colors.green.shade100);
    case 2:
      return Icon(Icons.warning, color: Colors.orange.shade100);
    default:
      return Icon(Icons.error, color: Colors.red.shade100);
  }
}

/// 🔥 TASK TYPE BO'YICHA FILTER
String getTypeName(int type) {
  switch (type) {
    case 1:
      return "Ежедневно";
    case 2:
      return "Еженедельно: ";
    case 3:
      return "Ежемесячно: ";
    default:
      return "Unknown";
  }
}

String getWeekday(int date) {
  switch (date) {
    case 1:
      return "Пн";
    case 2:
      return "Вт";
    case 3:
      return "Ср";
    case 4:
      return "Чт";
    case 5:
      return "Пт";
    case 6:
      return "Сб";
    case 7:
      return "Вс";
    default:
      return "--";
  }
}

String getWeekdaysString(List<int>? days) {
  if (days == null || days.isEmpty) return "";
  // Har bir kunni 2 harf bilan qisqartirish
  return days.map((d) => getWeekday(d)).join(", ");
}
