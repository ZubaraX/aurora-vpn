import 'package:aurora/data/models/installed_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preinstalled launcher apps are not treated as system services', () {
    final youtube = InstalledApp.fromJson({
      'id': 'com.google.android.youtube',
      'name': 'YouTube',
      'isSystem': true,
      'hasLauncher': true,
    });

    expect(youtube.isSystem, isTrue);
    expect(youtube.hasLauncher, isTrue);
    expect(youtube.isSystemService, isFalse);
  });

  test('background system packages remain classified as services', () {
    const service = InstalledApp(
      id: 'com.android.system.service',
      name: 'Android service',
      isSystem: true,
      hasLauncher: false,
    );

    expect(service.isSystemService, isTrue);
  });
}
