import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Bosh sahifa va «Все задачи» bir joyda turishi uchun umumiy holat:
/// qaysi filial ochiq va ro'yxat tepasida qaysi vazifa (shablon) turibdi.
class TaskViewSync {
  TaskViewSync._();

  static int? filialId;

  /// Ro'yxat tepasidagi vazifaning shabloni (null — ro'yxat boshi)
  static int? templateId;

  /// Oshirilganda ochiq ro'yxat [templateId] ga scroll qiladi
  static final ValueNotifier<int> jumps = ValueNotifier(0);

  static void requestJump() => jumps.value++;

  /// Foydalanuvchi tabni o'zi almashtirdi — yangi filial, ro'yxat boshidan
  static void selectFilial(int id) {
    if (filialId == id) return;
    filialId = id;
    templateId = null;
  }
}

/// Bitta sahifadagi filial ro'yxatlari — kerak paytda ochiq ro'yxat
/// tepasidagi vazifani [TaskViewSync] ga yozish uchun.
class TaskSyncScope {
  final Map<int, int? Function()> _anchors = {};

  void capture() {
    final id = TaskViewSync.filialId;
    final anchor = id == null ? null : _anchors[id];
    if (anchor != null) TaskViewSync.templateId = anchor();
  }
}

/// Vazifalar ro'yxati uchun: tepadagi vazifani kuzatadi va [TaskViewSync]
/// so'raganda kerakli vazifaga scroll qiladi.
mixin TaskScrollSync<T extends StatefulWidget> on State<T> {
  final ScrollController syncController = ScrollController();
  final Map<int, GlobalKey> _keys = {};

  TaskSyncScope? get syncScope;
  int get syncFilialId;

  /// Ro'yxatdagi shablonlar (ekrandagi tartibda)
  List<int> get syncTemplateIds;

  bool get _isCurrent => TaskViewSync.filialId == syncFilialId;

  /// Vazifa kartasini o'rash uchun kalit (shablon bo'yicha)
  GlobalKey syncKey(int templateId) =>
      _keys.putIfAbsent(templateId, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    syncScope?._anchors[syncFilialId] = topVisibleTemplate;
    TaskViewSync.jumps.addListener(_onJump);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isCurrent && TaskViewSync.templateId != null) _onJump();
    });
  }

  @override
  void dispose() {
    final anchors = syncScope?._anchors;
    if (anchors?[syncFilialId] == topVisibleTemplate) {
      anchors!.remove(syncFilialId);
    }
    TaskViewSync.jumps.removeListener(_onJump);
    syncController.dispose();
    super.dispose();
  }

  void _onJump() {
    if (!mounted || !_isCurrent) return;
    final id = TaskViewSync.templateId;
    if (id != null) {
      revealTemplate(id);
    } else if (syncController.hasClients) {
      syncController.jumpTo(0);
    }
  }

  /// Scroll to'xtaganda tepadagi vazifani eslab qolamiz
  Widget syncScrollListener(Widget child) {
    return NotificationListener<ScrollEndNotification>(
      onNotification: (n) {
        if (n.depth == 0 && _isCurrent) {
          TaskViewSync.templateId = topVisibleTemplate();
        }
        return false;
      },
      child: child,
    );
  }

  /// Ro'yxat tepasida (yoki eng yaqin yuqorida) turgan vazifaning shabloni
  int? topVisibleTemplate() {
    if (!syncController.hasClients) return null;
    final pixels = syncController.position.pixels;
    if (pixels <= 1) return null;

    int? best;
    var bestOffset = double.negativeInfinity;
    for (final entry in _keys.entries) {
      final object = entry.value.currentContext?.findRenderObject();
      if (object == null || !object.attached) continue;
      final viewport = RenderAbstractViewport.maybeOf(object);
      if (viewport == null) continue;
      final offset = viewport.getOffsetToReveal(object, 0).offset;
      if (offset <= pixels + 24 && offset > bestOffset) {
        best = entry.key;
        bestOffset = offset;
      }
    }
    return best;
  }

  /// Vazifani ro'yxat tepasiga olib keladi. Ro'yxat dangasa quriladi —
  /// karta hali qurilmagan bo'lsa taxminiy joyga sakrab, qayta urinamiz.
  Future<void> revealTemplate(int templateId) async {
    final ids = syncTemplateIds;
    final index = ids.indexOf(templateId);
    if (index < 0) return;

    for (var attempt = 0; attempt < 8 && mounted; attempt++) {
      final context = _keys[templateId]?.currentContext;
      if (context != null) {
        await Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      if (syncController.hasClients) {
        final position = syncController.position;
        final target = ids.length <= 1
            ? 0.0
            : position.maxScrollExtent * index / (ids.length - 1);
        syncController.jumpTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      }
      await WidgetsBinding.instance.endOfFrame;
    }
  }
}
