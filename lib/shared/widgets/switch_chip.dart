import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const _iosGreen = Color(0xFF34C759);

/// Tugmaga o'xshash tanlov: chapda nom, o'ngda iPhone'dagidek yashil
/// kalitcha. Tugmaning istalgan joyi bosilsa — yonadi / o'chadi.
class SwitchChip extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SwitchChip({
    super.key,
    required this.label,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 48,
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: BoxDecoration(
            color: value ? const Color(0xFFF0FBF3) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value ? const Color(0xFFB7E9C4) : const Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
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

/// [SwitchChip]larni ikki teng ustunda joylaydi — ikkala tomon bir xil
/// kenglikda va bir xil oraliqda turadi.
class SwitchChipGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;

  const SwitchChipGrid({super.key, required this.children, this.spacing = 10});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i += 2) ...[
          if (i > 0) SizedBox(height: spacing),
          Row(
            children: [
              Expanded(child: children[i]),
              SizedBox(width: spacing),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
