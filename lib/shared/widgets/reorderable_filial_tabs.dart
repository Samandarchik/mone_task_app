import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';

/// Filial tablari — TabBar o'rniga. [canReorder] bo'lsa tabni bosib turib
/// chapga/o'ngga sudrab joyini almashtirish mumkin; yangi tartib
/// [onReorder] ga beriladi (saqlash — chaqiruvchining ishi).
class ReorderableFilialTabs extends StatelessWidget {
  final TabController controller;
  final List<FilialModel> filials;
  final bool canReorder;
  final ValueChanged<List<FilialModel>> onReorder;
  final ValueChanged<FilialModel>? onDoubleTap;
  final Widget? trailing;

  const ReorderableFilialTabs({
    super.key,
    required this.controller,
    required this.filials,
    required this.canReorder,
    required this.onReorder,
    this.onDoubleTap,
    this.trailing,
  });

  void _handleReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    if (newIndex == oldIndex) return;

    final selectedId =
        filials[controller.index.clamp(0, filials.length - 1)].filialId;
    final order = List<FilialModel>.from(filials);
    order.insert(newIndex, order.removeAt(oldIndex));
    onReorder(order);
    // Tanlangan filial o'zi bilan birga ko'chadi
    controller.index = order.indexWhere((f) => f.filialId == selectedId);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kTextTabBarHeight,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: filials.length,
          proxyDecorator: (child, _, _) => Material(
            color: Colors.white,
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            child: child,
          ),
          onReorder: _handleReorder,
          itemBuilder: (context, index) {
            final filial = filials[index];
            final selected = controller.index == index;
            return ReorderableDelayedDragStartListener(
              key: ValueKey(filial.filialId),
              index: index,
              enabled: canReorder,
              child: GestureDetector(
                onTap: () => controller.animateTo(index),
                onDoubleTap: onDoubleTap == null
                    ? null
                    : () => onDoubleTap!(filial),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: Border(
                      bottom: BorderSide(
                        width: 3,
                        color: selected
                            ? const Color(0xFF2563EB)
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    filial.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ),
            );
          },
          footer: trailing,
        ),
      ),
    );
  }
}
