import 'package:flutter/material.dart';

import 'enums.dart';

/// All persisted user preferences plus the currently selected node.
class VpnSettings {
  const VpnSettings({
    this.routingMode = RoutingMode.rule,
    this.perAppMode = PerAppMode.off,
    this.perAppSelected = const {},
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
    triggerApps: ((j['triggerApps'] as Map?) ?? const {}).map(
      (k, v) => MapEntry('$k', '$v'),
    ),
    triggerWifiProfiles: ((j['triggerWifiProfiles'] as Map?) ?? const {}).map(
      (k, v) => MapEntry('$k', '$v'),
    ),
    triggerMobileProfiles: _mobileProfiles(j['triggerMobileProfiles']),
    tunMode: j['tunMode'] as bool? ?? true,
    tunStack: _enum(TunStack.values, j['tunStack'], TunStack.mixed),
    bypassLan: j['bypassLan'] as bool? ?? true,
    blockAds: j['blockAds'] as bool? ?? false,
    ipv6: j['ipv6'] as bool? ?? false,
    dnsRemote: j['dnsRemote'] as String? ?? 'https://1.1.1.1/dns-query',
    dnsDirect: j['dnsDirect'] as String? ?? 'https://1.1.1.1/dns-query',
    autoConnect: j['autoConnect'] as bool? ?? false,
    killSwitch: j['killSwitch'] as bool? ?? true,
    activeNodeId: j['activeNodeId'] as String?,
    themeMode: _enum(ThemeMode.values, j['themeMode'], ThemeMode.dark),
    locale: j['locale'] as String? ?? 'ru',
  );

  /// Profile selected for a trigger app on the current connection type.
  /// Unknown/desktop connection types keep the legacy/default selection.
  String triggerProfileFor(String appId, String networkType) {
    final profiles = triggerProfilesFor(appId, networkType);
    return profiles.isEmpty ? '' : profiles.first;
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

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}
