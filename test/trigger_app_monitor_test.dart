import 'package:aurora/data/models/enums.dart';
import 'package:aurora/data/models/vpn_settings.dart';
import 'package:aurora/features/apps/trigger_app_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const settings = VpnSettings(
    triggerApps: {'com.example.video': '', 'com.example.chat': ''},
    triggerWifiProfiles: {
      'com.example.video': 'video-wifi',
      'com.example.chat': 'chat-wifi',
    },
    triggerMobileProfiles: {
      'com.example.video': ['video-mobile', 'video-mobile-backup'],
      'com.example.chat': ['chat-mobile'],
    },
  );

  test('opening a trigger switches an already connected VPN', () {
    final monitor = TriggerAppMonitor();

    final action = monitor.evaluate(
      settings: settings,
      runningIds: {'com.example.video'},
      networkType: 'wifi',
      connectionStatus: ConnectionStatus.connected,
      activeNodeId: 'manual-node',
    );

    expect(action?.appId, 'com.example.video');
    expect(action?.profileId, 'video-wifi');
  });

  test('moving between trigger apps selects the new app profile', () {
    final monitor = TriggerAppMonitor();
    monitor.evaluate(
      settings: settings,
      runningIds: {'com.example.video'},
      networkType: 'wifi',
      connectionStatus: ConnectionStatus.connected,
      activeNodeId: 'manual-node',
    );
    monitor.evaluate(
      settings: settings,
      runningIds: {},
      networkType: 'wifi',
      connectionStatus: ConnectionStatus.connected,
      activeNodeId: 'video-wifi',
    );

    final action = monitor.evaluate(
      settings: settings,
      runningIds: {'com.example.chat'},
      networkType: 'wifi',
      connectionStatus: ConnectionStatus.connected,
      activeNodeId: 'video-wifi',
    );

    expect(action?.profileId, 'chat-wifi');
  });

  test('network change switches the active trigger profile', () {
    final monitor = TriggerAppMonitor();
    monitor.evaluate(
      settings: settings,
      runningIds: {'com.example.video'},
      networkType: 'wifi',
      connectionStatus: ConnectionStatus.connected,
      activeNodeId: 'manual-node',
    );

    final action = monitor.evaluate(
      settings: settings,
      runningIds: {'com.example.video'},
      networkType: 'mobile',
      connectionStatus: ConnectionStatus.connected,
      activeNodeId: 'video-wifi',
    );

    expect(action?.profileId, 'video-mobile');
    expect(action?.profileIds, ['video-mobile', 'video-mobile-backup']);
  });

  test('same active profile does not reconnect', () {
    final monitor = TriggerAppMonitor();

    final action = monitor.evaluate(
      settings: settings,
      runningIds: {'com.example.video'},
      networkType: 'wifi',
      connectionStatus: ConnectionStatus.connected,
      activeNodeId: 'video-wifi',
    );

    expect(action, isNull);
  });

  test('active mobile backup does not cause an unnecessary reconnect', () {
    final monitor = TriggerAppMonitor();

    final action = monitor.evaluate(
      settings: settings,
      runningIds: {'com.example.video'},
      networkType: 'mobile',
      connectionStatus: ConnectionStatus.connected,
      activeNodeId: 'video-mobile-backup',
    );

    expect(action, isNull);
  });

  group('no-VPN per network', () {
    const noVpnSettings = VpnSettings(
      triggerApps: {'com.example.video': ''},
      // VPN on Wi-Fi, but no VPN on mobile data.
      triggerWifiProfiles: {'com.example.video': 'video-wifi'},
      triggerMobileProfiles: {
        'com.example.video': [kTriggerNoVpn],
      },
    );

    test('opening on a no-VPN network tears an active tunnel down', () {
      final monitor = TriggerAppMonitor();
      final action = monitor.evaluate(
        settings: noVpnSettings,
        runningIds: {'com.example.video'},
        networkType: 'mobile',
        connectionStatus: ConnectionStatus.connected,
        activeNodeId: 'video-wifi',
      );
      expect(action?.disconnect, isTrue);
      expect(action?.profileIds, isEmpty);
    });

    test('no-VPN network does nothing when already disconnected', () {
      final monitor = TriggerAppMonitor();
      final action = monitor.evaluate(
        settings: noVpnSettings,
        runningIds: {'com.example.video'},
        networkType: 'mobile',
        connectionStatus: ConnectionStatus.disconnected,
        activeNodeId: null,
      );
      expect(action, isNull);
    });

    test('switching from no-VPN mobile to Wi-Fi connects the Wi-Fi server', () {
      final monitor = TriggerAppMonitor();
      monitor.evaluate(
        settings: noVpnSettings,
        runningIds: {'com.example.video'},
        networkType: 'mobile',
        connectionStatus: ConnectionStatus.disconnected,
        activeNodeId: null,
      );
      final action = monitor.evaluate(
        settings: noVpnSettings,
        runningIds: {'com.example.video'},
        networkType: 'wifi',
        connectionStatus: ConnectionStatus.disconnected,
        activeNodeId: null,
      );
      expect(action?.disconnect, isFalse);
      expect(action?.profileId, 'video-wifi');
    });
  });
}
