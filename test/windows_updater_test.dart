import 'package:flutter_test/flutter_test.dart';
import 'package:mone_task_app/core/update/windows_updater.dart';

void main() {
  test('Release tegidan versiya va build', () {
    expect(WindowsUpdater.buildFromTag('windows-0.3.8-308'), 308);
    expect(WindowsUpdater.versionFromTag('windows-0.3.8-308'), '0.3.8');
    expect(WindowsUpdater.buildFromTag('v0.3.8'), isNull);
    expect(WindowsUpdater.buildFromTag('windows-0.3.8-abc'), isNull);
  });
}
