import 'dart:convert';

import 'package:mone_task_app/worker/model/user_model.dart';

import 'base_storage.dart';

final class TokenStorage {
  static const String _token = 'access_token';
  static const String _refreshToken = 'refresh_token';
  static const String _user = 'user';
  // Super admin boshqa profilga kirganda o'z sessiyasi shu yerda saqlanadi
  static const String _adminToken = 'super_admin_token';
  static const String _adminUser = 'super_admin_user';
  // Super admin profil tugmasi bilan o'tadigan akkauntning login kodi
  static const String _linkedCode = 'super_admin_linked_code';
  final BaseStorage _baseStorage;

  TokenStorage(this._baseStorage);

  // Token methods
  Future<void> putToken(String token) async {
    await _baseStorage.putString(key: _token, value: token);
  }

  Future<void> putUserData(Map value) async {
    await _baseStorage.putUserData(key: _user, value: value);
  }

  Future<void> putRefreshToken(String refreshToken) async {
    await _baseStorage.putString(key: _refreshToken, value: refreshToken);
  }

  UserModel? getUserData() {
    final data = _baseStorage.getString(key: _user);
    if (data.isEmpty) return null;
    return UserModel.fromJson(jsonDecode(data));
  }

  Future<String> getToken() async {
    return _baseStorage.getString(key: _token);
  }

  Future<String> getRefreshToken() async {
    return _baseStorage.getString(key: _refreshToken);
  }

  Future<void> removeToken() async {
    await _baseStorage.remove(key: _token);
    // Chiqib ketilsa (yoki sessiya bekor bo'lsa) super admin sessiyasi
    // qurilmada qolib ketmasin
    await clearSuperAdminSession();
  }

  // Super admin → boshqa profil → orqaga qaytish

  /// Boshqa profilga kirishdan oldin joriy super admin sessiyasini saqlaydi.
  Future<void> saveSuperAdminSession() async {
    await _baseStorage.putString(
      key: _adminToken,
      value: _baseStorage.getString(key: _token),
    );
    await _baseStorage.putString(
      key: _adminUser,
      value: _baseStorage.getString(key: _user),
    );
  }

  /// Super admin boshqa profil nomidan kirgan bo'lsa — super admin ma'lumoti.
  UserModel? getSuperAdminSessionUser() {
    final token = _baseStorage.getString(key: _adminToken);
    final data = _baseStorage.getString(key: _adminUser);
    if (token.isEmpty || data.isEmpty) return null;
    return UserModel.fromJson(jsonDecode(data));
  }

  /// Super admin sessiyasini qaytaradi va saqlangan nusxani o'chiradi.
  Future<UserModel?> restoreSuperAdminSession() async {
    final user = getSuperAdminSessionUser();
    if (user == null) return null;
    await _baseStorage.putString(
      key: _token,
      value: _baseStorage.getString(key: _adminToken),
    );
    await _baseStorage.putString(
      key: _user,
      value: _baseStorage.getString(key: _adminUser),
    );
    await clearSuperAdminSession();
    return user;
  }

  String getLinkedAccountCode() => _baseStorage.getString(key: _linkedCode);

  Future<void> putLinkedAccountCode(String code) async {
    if (code.isEmpty) {
      await _baseStorage.remove(key: _linkedCode);
    } else {
      await _baseStorage.putString(key: _linkedCode, value: code);
    }
  }

  Future<void> clearSuperAdminSession() async {
    await _baseStorage.remove(key: _adminToken);
    await _baseStorage.remove(key: _adminUser);
  }

  Future<void> removeRefreshToken() async {
    await _baseStorage.remove(key: _refreshToken);
  }
}
