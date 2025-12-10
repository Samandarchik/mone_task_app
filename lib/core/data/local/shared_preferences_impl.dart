import 'package:shared_preferences/shared_preferences.dart';
import 'package:mone_task_app/core/data/local/base_storage.dart';

final class SharedPreferencesImpl implements BaseStorage {
  final SharedPreferences _pref;

  SharedPreferencesImpl(this._pref);

  @override
  Future<void> clear() async {
    await _pref.clear();
  }

  @override
  String getString({required String key}) {
    return _pref.getString(key) ?? '';
  }

  @override
  Future<void> putString({required String key, required String value}) async {
    await _pref.setString(key, value);
  }

  @override
  Future<void> remove({required String key}) async {
    await _pref.remove(key);
  }

  @override
  bool getBool({required String key}) {
    return _pref.getBool(key) ?? false;
  }

  @override
  Future<void> putBool({required String key, required bool value}) async {
    await _pref.setBool(key, value);
  }

  @override
  Future<void> putUserData({required String key, required String value}) async {
    await _pref.setString(key, value);
  }
}
