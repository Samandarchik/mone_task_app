import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Foydalanuvchi bir nechta filialga biriktirilgan bo'lsa — login dan keyin
/// bittasini tanlaydi. Tanlangan filial shu yerda saqlanadi va asosiy
/// ekranlar (worker / admin) shunga qarab filtrlanadi.
class ActiveFilial {
  ActiveFilial._();

  static const String _key = 'active_filial_v1';

  static int? _id;
  static String? _name;

  /// Tanlangan filial id si (yo'q bo'lsa — null = barcha filiallar)
  static int? get id => _id;

  /// Tanlangan filial nomi (ko'rsatish uchun)
  static String? get name => _name;

  static bool get hasSelection => _id != null;

  /// App ishga tushganda chaqiriladi — saqlangan tanlovni xotiraga yuklaydi.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _id = null;
      _name = null;
      return;
    }
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _id = j['id'] as int?;
      _name = j['name'] as String?;
    } catch (_) {
      _id = null;
      _name = null;
    }
  }

  /// Filial tanlandi — xotira va diskka yoziladi.
  static Future<void> set(int id, String? name) async {
    _id = id;
    _name = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({'id': id, 'name': name}));
  }

  /// Tanlovni tozalash (logout yoki super_admin = barcha filiallar).
  static Future<void> clear() async {
    _id = null;
    _name = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
