import 'package:aurora/data/models/vpn_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrates v1.6.0 subId-scoped node ids back to the stable id', () {
    // v1.6.0 stored ids as <subId>_<hash>_<index>; the stable id is
    // <hash>_<index>. fromJson must strip the subId so saved trigger
    // profiles / zone rules / active selection keep matching their node.
    final json = {
      'activeNodeId': 'sub1_abc123_0',
      'triggerApps': {'com.example.app': 'sub1_abc123_0'},
      'triggerWifiProfiles': {'com.example.app': 'sub1_abc123_0'},
      'triggerMobileProfiles': {
        'com.example.app': ['sub1_abc123_0', 'sub1_def456_1'],
      },
      'domainZoneRules': {'ru': 'sub1_abc123_0', 'com': 'direct'},
    };
    final s = VpnSettings.fromJson(json);
    expect(s.activeNodeId, 'abc123_0');
    expect(s.triggerApps['com.example.app'], 'abc123_0');
    expect(s.triggerWifiProfiles['com.example.app'], 'abc123_0');
    expect(s.triggerMobileProfiles['com.example.app'], ['abc123_0', 'def456_1']);
    expect(s.domainZoneRules['ru'], 'abc123_0');
    // Non-node targets and already-stable ids are untouched / idempotent.
    expect(s.domainZoneRules['com'], 'direct');
    expect(VpnSettings.migrateNodeId('abc123_0'), 'abc123_0');
    expect(VpnSettings.migrateNodeId('direct'), 'direct');
  });

  test('trigger profiles are selected by upstream network type', () {
    const settings = VpnSettings(
      triggerApps: {'com.example.app': 'fallback'},
      triggerWifiProfiles: {'com.example.app': 'wifi-node'},
      triggerMobileProfiles: {
        'com.example.app': ['mobile-node', 'mobile-backup'],
      },
    );

    expect(settings.triggerProfileFor('com.example.app', 'wifi'), 'wifi-node');
    expect(
      settings.triggerProfileFor('com.example.app', 'mobile'),
      'mobile-node',
    );
    expect(settings.triggerProfilesFor('com.example.app', 'mobile'), [
      'mobile-node',
      'mobile-backup',
    ]);
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
      triggerMobileProfiles: {
        'com.example.app': ['mobile-node', 'mobile-backup'],
      },
    );

    final restored = VpnSettings.fromJson(original.toJson());

    expect(restored.triggerWifiProfiles, original.triggerWifiProfiles);
    expect(restored.triggerMobileProfiles, original.triggerMobileProfiles);
  });

  test('legacy single mobile profile migrates to a list', () {
    final restored = VpnSettings.fromJson({
      'triggerApps': {'com.example.app': ''},
      'triggerMobileProfiles': {'com.example.app': 'old-mobile-node'},
    });

    expect(restored.triggerProfilesFor('com.example.app', 'mobile'), [
      'old-mobile-node',
    ]);
  });

  test('mobile profile pool is unique and capped at twenty', () {
    final restored = VpnSettings.fromJson({
      'triggerApps': {'com.example.app': ''},
      'triggerMobileProfiles': {
        'com.example.app': [for (var i = 0; i < 25; i++) 'node-$i', 'node-0'],
      },
    });

    final profiles = restored.triggerProfilesFor('com.example.app', 'mobile');
    expect(profiles, hasLength(20));
    expect(profiles.toSet(), hasLength(20));
    expect(profiles.first, 'node-0');
    expect(profiles.last, 'node-19');
  });
}
