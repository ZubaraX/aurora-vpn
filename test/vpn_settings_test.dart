import 'package:aurora/data/models/vpn_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trigger profiles are selected by upstream network type', () {
    const settings = VpnSettings(
      triggerApps: {'com.example.app': 'fallback'},
      triggerWifiProfiles: {'com.example.app': 'wifi-node'},
      triggerMobileProfiles: {'com.example.app': 'mobile-node'},
    );

    expect(settings.triggerProfileFor('com.example.app', 'wifi'), 'wifi-node');
    expect(
      settings.triggerProfileFor('com.example.app', 'mobile'),
      'mobile-node',
    );
    expect(settings.triggerProfileFor('com.example.app', 'other'), 'fallback');
  });

  test('legacy trigger profile remains the fallback after JSON migration', () {
    final settings = VpnSettings.fromJson({
      'triggerApps': {'com.example.app': 'legacy-node'},
    });

    expect(
      settings.triggerProfileFor('com.example.app', 'wifi'),
      'legacy-node',
    );
    expect(
      settings.triggerProfileFor('com.example.app', 'mobile'),
      'legacy-node',
    );
  });

  test('network-specific trigger profiles survive JSON round-trip', () {
    const original = VpnSettings(
      triggerApps: {'com.example.app': ''},
      triggerWifiProfiles: {'com.example.app': 'wifi-node'},
      triggerMobileProfiles: {'com.example.app': 'mobile-node'},
    );

    final restored = VpnSettings.fromJson(original.toJson());

    expect(restored.triggerWifiProfiles, original.triggerWifiProfiles);
    expect(restored.triggerMobileProfiles, original.triggerMobileProfiles);
  });
}
