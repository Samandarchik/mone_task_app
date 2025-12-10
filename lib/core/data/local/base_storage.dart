abstract class BaseStorage {
  Future<void> putString({required String key, required String value});
  String getString({required String key});
  Future<void> remove({required String key});
  Future<void> clear();
  Future<void> putBool({required String key, required bool value});
  bool getBool({required String key});
  Future<void>putUserData({required String key, required String value});
}
