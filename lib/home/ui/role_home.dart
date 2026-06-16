import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/provider/admin_task_ui.dart';
import 'package:mone_task_app/core/data/local/active_filial.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/home/ui/filial_select_page.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:mone_task_app/worker/ui/task_worker_ui.dart';

/// Rol bo'yicha asosiy ekran (filial allaqachon tanlangan deb hisoblanadi).
Widget roleHome(String role) {
  if (role == 'super_admin' || role == 'checker') return const AdminTaskUi();
  if (role == 'worker') return const TaskWorkerUi();
  return const LoginPage();
}

/// Auth dan keyin ko'rsatiladigan birinchi ekran.
///
/// - super_admin / checker → barcha filiallarni ko'radi, tanlov shart emas.
/// - worker: filialIds 2+ bo'lsa → filial tanlash ekrani.
/// - worker: 1 ta bo'lsa → o'sha filial aktiv qilinadi, to'g'ridan-to'g'ri asosiy ekran.
Widget landingForUser(UserModel user) {
  final role = user.role;
  if (role != 'super_admin' && role != 'checker' && role != 'worker') {
    return const LoginPage();
  }

  // super_admin va checker (Корректор) barcha filiallarni ko'radi va
  // tekshira oladi — filial tanlash shart emas.
  if (role == 'super_admin' || role == 'checker') {
    ActiveFilial.clear();
    return roleHome(role);
  }

  final ids = user.filialIds ?? const <int>[];

  if (ids.length > 1) {
    // Tanlov majburiy — eski aktiv filial endi mavjud bo'lmasligi mumkin
    if (ActiveFilial.id == null || !ids.contains(ActiveFilial.id)) {
      return FilialSelectPage(role: role, allowedIds: ids);
    }
    // Avval tanlangan va hali ham amal qiladi — to'g'ridan-to'g'ri kiramiz
    return roleHome(role);
  }

  if (ids.length == 1) {
    // Bitta filial — id bo'yicha filtrlash kifoya. Nom faqat shu filialники
    // bo'lsa saqlanadi (boshqa filialdan qolgan eski nom ko'rsatilmasin).
    final keepName = ActiveFilial.id == ids.first ? ActiveFilial.name : null;
    ActiveFilial.set(ids.first, keepName);
  } else {
    ActiveFilial.clear();
  }
  return roleHome(role);
}

/// WS 'user_updated' hodisasini qo'llaydi: hodisa joriy foydalanuvchiga tegishli
/// bo'lsa, saqlangan UserModel ni yangi ruxsatlar bilan yangilaydi va yangilangan
/// modelni qaytaradi. Aks holda null.
UserModel? applyUserUpdateEvent(Map<String, dynamic> data) {
  final ts = sl<TokenStorage>();
  final current = ts.getUserData();
  if (current == null) return null;

  final rawId = data['userId'];
  final eventUserId = rawId is int ? rawId : int.tryParse('${rawId ?? ''}');
  if (eventUserId == null || eventUserId != current.userId) return null;

  List<int>? newIds;
  final rawIds = data['filialIds'];
  if (rawIds is List) {
    newIds = rawIds
        .map((e) => e is int ? e : int.tryParse('$e') ?? 0)
        .where((e) => e > 0)
        .toList();
  }

  final newRole =
      data['role'] is String && (data['role'] as String).isNotEmpty
          ? data['role'] as String
          : current.role;

  final updated = current.copyWith(filialIds: newIds, role: newRole);
  ts.putUserData(updated.toJson());

  // Aktiv filial endi ruxsat ro'yxatida bo'lmasa — tozalaymiz (qayta tanlanadi).
  final ids = updated.filialIds ?? const <int>[];
  if (ActiveFilial.id != null && !ids.contains(ActiveFilial.id)) {
    ActiveFilial.clear();
  }
  return updated;
}
