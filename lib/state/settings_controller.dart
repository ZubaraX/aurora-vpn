import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/storage.dart';
import '../data/models/enums.dart';
import '../data/models/vpn_settings.dart';
import 'providers.dart';

/// Owns [VpnSettings] and persists every mutation immediately.
class SettingsController extends StateNotifier<VpnSettings> {
  SettingsController(this._storage) : super(_load(_storage));

  final Storage _storage;

  static VpnSettings _load(Storage s) {
    final map = s.readMap(Storage.kSettings);
    return map == null ? const VpnSettings() : VpnSettings.fromJson(map);
  }

  void _commit(VpnSettings next) {
    state = next;
    _storage.writeJson(Storage.kSettings, state.toJson());
  }

  void setRoutingMode(RoutingMode mode) =>
      _commit(state.copyWith(routingMode: mode));

  void setPerAppMode(PerAppMode mode) =>
      _commit(state.copyWith(perAppMode: mode));

  void toggleApp(String id) {
    final set = {...state.perAppSelected};
    set.contains(id) ? set.remove(id) : set.add(id);
    _commit(state.copyWith(perAppSelected: set));
  }

  void clearApps() => _commit(state.copyWith(perAppSelected: {}));

  void selectApps(Iterable<String> ids) => _commit(
    state.copyWith(perAppSelected: {...state.perAppSelected, ...ids}),
  );

  void deselectApps(Iterable<String> ids) {
    final set = {...state.perAppSelected}..removeAll(ids);
    _commit(state.copyWith(perAppSelected: set));
  }

  void toggleTriggerApp(String id) {
    final map = {...state.triggerApps};
    final wifi = {...state.triggerWifiProfiles};
    final mobile = {...state.triggerMobileProfiles};
    if (map.containsKey(id)) {
      map.remove(id);
      wifi.remove(id);
      mobile.remove(id);
    } else {
      map[id] = '';
    }
    _commit(
      state.copyWith(
        triggerApps: map,
        triggerWifiProfiles: wifi,
        triggerMobileProfiles: mobile,
      ),
    );
  }

  /// Sets which server a trigger app uses on Wi-Fi.
  void setTriggerWifiProfile(String id, String nodeId) {
    final map = {...state.triggerWifiProfiles};
    map[id] = nodeId;
    _commit(state.copyWith(triggerWifiProfiles: map));
  }

  /// Sets the ordered mobile failover pool (up to 20 servers).
  void setTriggerMobileProfiles(String id, Iterable<String> nodeIds) {
    final map = {...state.triggerMobileProfiles};
    map[id] = nodeIds
        .where((nodeId) => nodeId.isNotEmpty)
        .toSet()
        .take(20)
        .toList();
    _commit(state.copyWith(triggerMobileProfiles: map));
  }

  /// Backward-compatible single-selection entry point.
  void setTriggerMobileProfile(String id, String nodeId) =>
      setTriggerMobileProfiles(id, nodeId.isEmpty ? const [] : [nodeId]);

  void clearTriggerApps() => _commit(
    state.copyWith(
      triggerApps: {},
      triggerWifiProfiles: {},
      triggerMobileProfiles: {},
    ),
  );

  void setActiveNode(String? id) =>
      _commit(state.copyWith(activeNodeId: id, clearActiveNode: id == null));

  void setTunMode(bool v) => _commit(state.copyWith(tunMode: v));
  void setTunStack(TunStack v) => _commit(state.copyWith(tunStack: v));
  void setBypassLan(bool v) => _commit(state.copyWith(bypassLan: v));
  void setBlockAds(bool v) => _commit(state.copyWith(blockAds: v));
  void setIpv6(bool v) => _commit(state.copyWith(ipv6: v));
  void setAutoConnect(bool v) => _commit(state.copyWith(autoConnect: v));
  void setKillSwitch(bool v) => _commit(state.copyWith(killSwitch: v));
  void setDnsRemote(String v) => _commit(state.copyWith(dnsRemote: v));
  void setDnsDirect(String v) => _commit(state.copyWith(dnsDirect: v));
  void setThemeMode(ThemeMode v) => _commit(state.copyWith(themeMode: v));
  void setLocale(String v) => _commit(state.copyWith(locale: v));
}

final settingsProvider = StateNotifierProvider<SettingsController, VpnSettings>(
  (ref) {
    return SettingsController(ref.watch(storageProvider));
  },
);
