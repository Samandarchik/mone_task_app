import 'package:flutter/material.dart';

/// Bundan tor ekranda sarlavha tugmalar bilan yonma-yon sig'maydi
const double kCompactHeaderWidth = 600;

const double _phoneTitleSize = 15.5;
const double _minTitleSize = 13;

/// Vazifa matni shrifti: telefonda ekran kengligi va matn uzunligiga moslashadi
/// (kesilmaydi — to'liq o'qilishi kerak), katta ekranda doim [wide].
double taskTitleFontSize(
  BuildContext context,
  String text, {
  required double wide,
}) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= kCompactHeaderWidth) return wide;

  var size = _phoneTitleSize;
  if (width < 360) size -= 1;
  if (text.length > 140) {
    size -= 2;
  } else if (text.length > 70) {
    size -= 1;
  }
  return size < _minTitleSize ? _minTitleSize : size;
}

/// Karta sarlavhasi. Katta ekranda hammasi bir qatorda; telefonda tugmalar
/// tepada, matn esa ostida to'liq kenglikda — aks holda tugmalar matnga
/// atigi ~130dp qoldiradi va u tor ustunga aylanib ketadi.
class TaskCardHeader extends StatelessWidget {
  /// Vazifa raqami
  final Widget leading;

  /// Vazifa matni (va kerak bo'lsa uning ostidagi ma'lumotlar)
  final Widget title;

  /// Boshqaruv tugmalari
  final List<Widget> actions;

  const TaskCardHeader({
    super.key,
    required this.leading,
    required this.title,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= kCompactHeaderWidth) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(child: title),
          ...actions,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [leading, const Spacer(), ...actions]),
        const SizedBox(height: 8),
        title,
      ],
    );
  }
}
