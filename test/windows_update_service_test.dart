import 'package:flutter_test/flutter_test.dart';
import 'package:mone_task_app/shared/services/windows_update_service.dart';

void main() {
  test('Versiyalarni solishtirish (X.Y.Z)', () {
    expect(WindowsUpdateService.isNewerVersion('0.3.10', '0.3.9'), isTrue);
    expect(WindowsUpdateService.isNewerVersion('0.4.0', '0.3.9'), isTrue);
    expect(WindowsUpdateService.isNewerVersion('0.3.9', '0.3.9'), isFalse);
    expect(WindowsUpdateService.isNewerVersion('0.3.8', '0.3.9'), isFalse);
  });
}
