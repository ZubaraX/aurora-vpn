import 'package:flutter/material.dart';

import 'enums.dart';

/// Sentinel trigger-app profile meaning "keep the VPN OFF on this network".
/// Lets a trigger use the tunnel on one network type but not the other.
const String kTriggerNoVpn = '__novpn__';

/// All persisted user preferences plus the currently selected node.
class VpnSettings {
  const VpnSettings({
    this.routingMode = RoutingMode.rule,
    this.perAppMode = PerAppMode.off,
    this.perAppSelected = const {},
    this.collapsedSubs = const {},
    this.domainZoneRules = const {},
    this.triggerApps = const {},
    this.triggerWifiProfiles = const {},
    this.triggerMobileProfiles = const <String, List<String>>{},
    this.tunMode = true,
    this.tunStack = TunStack.mixed,
    this.bypassLan = true,
    this.blockAds = false,
    this.ipv6 = false,
    this.dnsRemote = 'https://1.1.1.1/dns-query',
    this.dnsDirect = 'https://1.1.1.1/dns-query',
    this.autoConnect = false,
    this.killSwitch = true,
    this.activeNodeId,
    this.themeMode = ThemeMode.dark,
    this.locale = 'ru',
  });

  final RoutingMode routingMode;
  final PerAppMode perAppMode;
  final Set<String> perAppSelected;

  /// Ids of subscriptions whose server list is collapsed/hidden in the UI.
  final Set<String> collapsedSubs;

  /// User routing rules keyed by domain zone/suffix (e.g. `ru`, `рф`,
  /// `google.com`) → target: `direct`, `proxy` or `block`. Applied ahead of the
  /// default rule-set routing so a zone always wins.
  final Map<String, String> domainZoneRules;

  /// Apps whose launch auto-connects the tunnel, mapped to the node id to
  /// connect (empty value = use the currently selected server). The value is
  /// also the backward-compatible fallback for installations saved before
  /// separate Wi-Fi and mobile profiles were introduced.
  final Map<String, String> triggerApps;
  final Map<String, String> triggerWifiProfiles;
  final Map<String, List<String>> triggerMobileProfiles;
  final bool tunMode;
  final TunStack tunStack;
  final bool bypassLan;
  final bool blockAds;
  final bool ipv6;
  final String dnsRemote;
  final String dnsDirect;
  final bool autoConnect;
  final bool killSwitch;
  final String? activeNodeId;
  final ThemeMode themeMode;
  final String locale;

  VpnSettings copyWith({
    RoutingMode? routingMode,
    PerAppMode? perAppMode,
    Set<String>? perAppSelected,
    Set<String>? collapsedSubs,
    Map<String, String>? domainZoneRules,
    Map<String, String>? triggerApps,
    Map<String, String>? triggerWifiProfiles,
    Map<String, List<String>>? triggerMobileProfiles,
    bool? tunMode,
    TunStack? tunStack,
    bool? bypassLan,
    bool? blockAds,
    bool? ipv6,
    String? dnsRemote,
    String? dnsDirect,
    bool? autoConnect,
    bool? killSwitch,
    String? activeNodeId,
    bool clearActiveNode = false,
    ThemeMode? themeMode,
    String? locale,
  }) => VpnSettings(
    routingMode: routingMode ?? this.routingMode,
    perAppMode: perAppMode ?? this.perAppMode,
    perAppSelected: perAppSelected ?? this.perAppSelected,
    collapsedSubs: collapsedSubs ?? this.collapsedSubs,
    domainZoneRules: domainZoneRules ?? this.domainZoneRules,
    triggerApps: triggerApps ?? this.triggerApps,
    triggerWifiProfiles: triggerWifiProfiles ?? this.triggerWifiProfiles,
    triggerMobileProfiles: triggerMobileProfiles ?? this.triggerMobileProfiles,
    tunMode: tunMode ?? this.tunMode,
    tunStack: tunStack ?? this.tunStack,
    bypassLan: bypassLan ?? this.bypassLan,
    blockAds: blockAds ?? this.blockAds,
    ipv6: ipv6 ?? this.ipv6,
    dnsRemote: dnsRemote ?? this.dnsRemote,
    dnsDirect: dnsDirect ?? this.dnsDirect,
    autoConnect: autoConnect ?? this.autoConnect,
    killSwitch: killSwitch ?? this.killSwitch,
    activeNodeId: clearActiveNode ? null : (activeNodeId ?? this.activeNodeId),
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
  );

  Map<String, dynamic> toJson() => {
    'routingMode': routingMode.name,
    'perAppMode': perAppMode.name,
    'perAppSelected': perAppSelected.toList(),
    'collapsedSubs': collapsedSubs.toList(),
    'domainZoneRules': domainZoneRules,
    'triggerApps': triggerApps,
    'triggerWifiProfiles': triggerWifiProfiles,
    'triggerMobileProfiles': triggerMobileProfiles,
    'tunMode': tunMode,
    'tunStack': tunStack.name,
    'bypassLan': bypassLan,
    'blockAds': blockAds,
    'ipv6': ipv6,
    'dnsRemote': dnsRemote,
    'dnsDirect': dnsDirect,
    'autoConnect': autoConnect,
    'killSwitch': killSwitch,
    'activeNodeId': activeNodeId,
    'themeMode': themeMode.name,
    'locale': locale,
  };

  factory VpnSettings.fromJson(Map<String, dynamic> j) => VpnSettings(
    routingMode: _enum(RoutingMode.values, j['routingMode'], RoutingMode.rule),
    perAppMode: _enum(PerAppMode.values, j['perAppMode'], PerAppMode.off),
    perAppSelected: ((j['perAppSelected'] as List?)?.cast<String>() ?? const [])
        .toSet(),
    collapsedSubs: ((j['collapsedSubs'] as List?)?.cast<String>() ?? const [])
        .toSet(),
    domainZoneRules: _migValues(_stringMap(j['domainZoneRules'])),
    triggerApps: _migValues(_stringMap(j['triggerApps'])),
    triggerWifiProfiles: _migValues(_stringMap(j['triggerWifiProfiles'])),
    triggerMobileProfiles: _mobileProfiles(j['triggerMobileProfiles'])
        .map((k, v) => MapEntry(k, v.map(migrateNodeId).toList())),
    tunMode: j['tunMode'] as bool? ?? true,
    tunStack: _enum(TunStack.values, j['tunStack'], TunStack.mixed),
    bypassLan: j['bypassLan'] as bool? ?? true,
    blockAds: j['blockAds'] as bool? ?? false,
    ipv6: j['ipv6'] as bool? ?? false,
    dnsRemote: j['dnsRemote'] as String? ?? 'https://1.1.1.1/dns-query',
    dnsDirect: j['dnsDirect'] as String? ?? 'https://1.1.1.1/dns-query',
    autoConnect: j['autoConnect'] as bool? ?? false,
    killSwitch: j['killSwitch'] as bool? ?? true,
    activeNodeId: j['activeNodeId'] == null
        ? null
        : migrateNodeId(j['activeNodeId'] as String),
    themeMode: _enum(ThemeMode.values, j['themeMode'], ThemeMode.dark),
    locale: j['locale'] as String? ?? 'ru',
  );

  /// Profile selected for a trigger app on the current connection type.
  /// Unknown/desktop connection types keep the legacy/default selection.
  String triggerProfileFor(String appId, String networkType) {
    final profiles = triggerProfilesFor(appId, networkType);
    return profiles.isEmpty ? '' : profiles.first;
  }

  /// Whether this trigger app should keep the VPN OFF on [networkType].
  bool triggerNoVpnFor(String appId, String networkType) {
    final ids = triggerProfilesFor(appId, networkType);
    return ids.length == 1 && ids.first == kTriggerNoVpn;
  }

  /// Ordered profiles selected for a trigger app and upstream network.
  ///
  /// Mobile supports up to 20 candidates. Old settings that stored one string
  /// are migrated to a one-item list by [_mobileProfiles].
  List<String> triggerProfilesFor(String appId, String networkType) {
    final fallback = triggerApps[appId] ?? '';
    final profiles = switch (networkType) {
      'wifi' => [triggerWifiProfiles[appId] ?? fallback],
      'mobile' =>
        triggerMobileProfiles[appId] ??
            (fallback.isEmpty ? const <String>[] : [fallback]),
      _ => [fallback],
    };
    return profiles.where((id) => id.isNotEmpty).toSet().take(20).toList();
  }

  static Map<String, List<String>> _mobileProfiles(Object? raw) {
    final source = raw is Map ? raw : const {};
    return source.map((key, value) {
      final ids = value is List
          ? value.map((id) => '$id')
          : ('$value'.isEmpty ? const <String>[] : ['$value']);
      return MapEntry(
        '$key',
        ids.where((id) => id.isNotEmpty).toSet().take(20).toList(),
      );
    });
  }

  /// Migrates a persisted node id from any earlier scheme to the current
  /// position-independent id (`<hash>`), so trigger profiles / zone rules / the
  /// active selection saved before keep matching their node:
  ///   `<hash>_<index>`          (v1.5–v1.6.2)  -> `<hash>`   (2 parts)
  ///   `<subId>_<hash>_<index>`  (v1.6.0)       -> `<hash>`   (3 parts)
  ///   `<hash>` / `direct` / `proxy` / `block`  -> unchanged  (1 part)
  /// Idempotent, and non-node values (which never contain `_`) pass through.
  static String migrateNodeId(String id) {
    if (id.isEmpty) return id;
    final parts = id.split('_');
    if (parts.length == 2) return parts[0];
    if (parts.length >= 3) return parts[parts.length - 2];
    return id;
  }

  static Map<String, String> _migValues(Map<String, String> m) =>
      m.map((k, v) => MapEntry(k, migrateNodeId(v)));

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  /// Reads a {appId: nodeId} map, tolerating the legacy format where trigger
  /// apps were stored as a plain list of ids (migrated to empty profiles).
  static Map<String, String> _stringMap(Object? raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry('$k', '$v'));
    }
    if (raw is List) {
      return {for (final e in raw) '$e': ''};
    }
    return {};
  }
}
