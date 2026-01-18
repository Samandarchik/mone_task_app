import 'package:flutter/material.dart';

/// 🔥 STATUS COLOR
Color getStatusColor(int status) {
  switch (status) {
    case 3:
      return Colors.green.shade100;
    case 2:
      return Colors.orange.shade100;
    default:
      return Colors.red.shade100;
  }
}

/// 🔥 TASK TYPE BO'YICHA FILTER
String getTypeName(int type) {
  switch (type) {
    case 1:
      return "Ежедневно";
    case 2:
      return "Еженедельно";
    case 3:
      return "Ежемесячно";
    default:
      return "Unknown";
  }
}

String getWeekdayRu() {
  switch (DateTime.now().weekday) {
    case 1:
      return "Понедельник";
    case 2:
      return "Вторник";
    case 3:
      return "Среда";
    case 4:
      return "Четверг";
    case 5:
      return "Пятница";
    case 6:
      return "Суббота";
    case 7:
      return "Воскресенье";
    default:
      return "Неизвестно";
  }
}
