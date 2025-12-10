import 'base_storage.dart';

final class AppStorage {
  static const String _onBoarding = 'on_boarding';
  static const String _language = 'language';

  final BaseStorage _baseStorage;

  AppStorage(this._baseStorage);

  Future<void> setOnBoarding() async {
    await _baseStorage.putBool(key: _onBoarding, value: true);
  }

  Future<void> putOnBoarding(bool onBoarding) async {
    await _baseStorage.putBool(key: _onBoarding, value: onBoarding);
  }

  bool getOnBoarding() {
    return _baseStorage.getBool(key: _onBoarding);
  }

  Future<void> putLanguage(String language) async {
    await _baseStorage.putString(key: _language, value: language);
  }

  String getLanguage() {
    return _baseStorage.getString(key: _language);
  }
}
