import 'package:flutter/services.dart';

class NativeDialog {
  static const _channel = MethodChannel('native_dialog');

  static Future<bool> showDeleteDialog() async {
    final result = await _channel.invokeMethod<bool>('showDeleteDialog');
    return result ?? false;
  }
}
