import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const _iosGreen = Color(0xFF34C759);

/// Tugmaga o'xshash tanlov: chapda nom, o'ngda iPhone'dagidek yashil
/// kalitcha. Tugmaning istalgan joyi bosilsa — yonadi / o'chadi.
class SwitchChip extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Kalitcha oldida ko'rsatiladigan son (masalan, nechta odamda yoqilgan)
  final int? count;

  /// Nomdan oldin turadigan element (masalan, sudrash dastagi).
  final Widget? leading;

  const SwitchChip({
    super.key,
    required this.label,
    required this.value,
    this.onChanged,
    this.count,
    this.leading,
  });

  /// Shu tugmaning nusxasi, faqat [leading] almashtirilgan.
  SwitchChip withLeading(Widget leading) => SwitchChip(
    key: key,
    label: label,
    value: value,
    onChanged: onChanged,
    count: count,
    leading: leading,
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 52,
          padding: EdgeInsets.only(left: leading == null ? 14 : 4, right: 6),
          decoration: BoxDecoration(
            color: value ? const Color(0xFFF0FBF3) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value ? const Color(0xFFB7E9C4) : const Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 4)],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 8),
                _CountPill(count: count!, active: value),
              ],
              const SizedBox(width: 8),
              Transform.scale(
                scale: 0.8,
                child: CupertinoSwitch(
                  value: value,
                  activeTrackColor: _iosGreen,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final int count;
  final bool active;

  const _CountPill({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF1F9D45) : const Color(0xFF6B7280);
    return Tooltip(
      message: 'Доступ у $count чел.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFDDF5E4) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_rounded, size: 14, color: color),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [SwitchChip]larni ikki teng ustunda joylaydi — ikkala tomon bir xil
/// kenglikda va bir xil oraliqda turadi.
///
/// [onReorder] berilsa, har tugmada sudrash dastagi (⠿) chiqadi — uni
/// ushlab boshqa tugma ustiga sudrab joyini almashtirish mumkin. Tugmaning
/// o'zini bosib turib sudrash ham ishlaydi: `onReorder(eski, yangi)`.
class SwitchChipGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final void Function(int from, int to)? onReorder;

  const SwitchChipGrid({
    super.key,
    required this.children,
    this.spacing = 10,
    this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - spacing) / 2;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i += 2) ...[
              if (i > 0) SizedBox(height: spacing),
              Row(
                children: [
                  Expanded(child: _cell(i, columnWidth)),
                  SizedBox(width: spacing),
                  Expanded(
                    child: i + 1 < children.length
                        ? _cell(i + 1, columnWidth)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _cell(int index, double width) {
    var child = children[index];
    if (onReorder == null) return child;

    final feedback = Material(
      color: Colors.transparent,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: width, child: child),
    );
    if (child is SwitchChip) {
      child = child.withLeading(
        _DragHandle(index: index, feedback: feedback),
      );
    }

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onReorder!(details.data, index),
      builder: (context, candidates, _) => LongPressDraggable<int>(
        data: index,
        feedback: feedback,
        childWhenDragging: Opacity(opacity: 0.3, child: child),
        child: candidates.isEmpty
            ? child
            : DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2563EB), width: 2),
                ),
                child: child,
              ),
      ),
    );
  }
}

/// Sudrash dastagi: bosilishi bilanoq sudraladi (sichqoncha uchun qulay),
/// oddiy bosish kalitchani o'zgartirmaydi.
class _DragHandle extends StatelessWidget {
  final int index;
  final Widget feedback;

  const _DragHandle({required this.index, required this.feedback});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Перетащите, чтобы изменить порядок',
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {}, // bosish tugmaning o'ziga o'tib ketmasin
          child: Draggable<int>(
            data: index,
            feedback: feedback,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Icon(
                Icons.drag_indicator_rounded,
                size: 22,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
