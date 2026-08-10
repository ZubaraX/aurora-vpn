import 'package:aurora/data/models/vpn_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrates old node ids to the position-independent hash id', () {
    // Older ids embedded the list index (and, briefly, the subscription id).
    // fromJson strips them to the bare hash so saved trigger profiles / zone
    // rules / active selection keep matching their node after the id scheme
    // became position-independent.
    final json = {
      'activeNodeId': 'sub1_abc123_0', // v1.6.0: subId_hash_index
      'triggerApps': {'com.example.app': 'abc123_0'}, // v1.5–v1.6.2: hash_index
      'triggerWifiProfiles': {'com.example.app': 'abc123_5'}, // reordered index
      'triggerMobileProfiles': {
        'com.example.app': ['abc123_0', 'sub1_def456_1'],
      },
      'domainZoneRules': {'ru': 'sub1_abc123_0', 'com': 'direct'},
    };
    final s = VpnSettings.fromJson(json);
    expect(s.activeNodeId, 'abc123');
    expect(s.triggerApps['com.example.app'], 'abc123');
    // Same node saved at a different index still resolves to the same id.
    expect(s.triggerWifiProfiles['com.example.app'], 'abc123');
    expect(s.triggerMobileProfiles['com.example.app'], ['abc123', 'def456']);
    expect(s.domainZoneRules['ru'], 'abc123');
    // Non-node targets and already-stable ids pass through / are idempotent.
    expect(s.domainZoneRules['com'], 'direct');
    expect(VpnSettings.migrateNodeId('abc123'), 'abc123');
    expect(VpnSettings.migrateNodeId('direct'), 'direct');
  });

  test('fromJson tolerates unexpected field types without throwing', () {
    // A single bad type must not throw — that would send _load to blank
    // defaults and the next write would wipe every trigger profile.
    final s = VpnSettings.fromJson({
      'perAppSelected': {'not': 'a list'}, // Map instead of List
      'collapsedSubs': 'oops', // String instead of List
      'tunMode': 1, // int instead of bool
      'blockAds': 'true', // String instead of bool
      'activeNodeId': 123, // int instead of String
      'triggerApps': ['a', 'b'], // legacy List instead of Map
      'triggerWifiProfiles': {'app': 'node'},
      'dnsRemote': 42, // int instead of String
    });
    expect(s.perAppSelected, isEmpty);
    expect(s.collapsedSubs, isEmpty);
    expect(s.tunMode, true);
    expect(s.blockAds, true);
    expect(s.activeNodeId, '123');
    expect(s.triggerApps.keys, containsAll(['a', 'b']));
    expect(s.triggerWifiProfiles['app'], 'node');
    expect(s.dnsRemote, '42');
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
