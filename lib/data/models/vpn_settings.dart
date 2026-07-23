import 'package:flutter/material.dart';

import 'enums.dart';

/// All persisted user preferences plus the currently selected node.
class VpnSettings {
  const VpnSettings({
    this.routingMode = RoutingMode.rule,
    this.perAppMode = PerAppMode.off,
    this.perAppSelected = const {},
    this.triggerApps = const {},
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

  /// Apps whose launch auto-connects the tunnel (trigger apps).
  final Set<String> triggerApps;
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
    Set<String>? triggerApps,
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
  }) =>
      VpnSettings(
        routingMode: routingMode ?? this.routingMode,
        perAppMode: perAppMode ?? this.perAppMode,
        perAppSelected: perAppSelected ?? this.perAppSelected,
        triggerApps: triggerApps ?? this.triggerApps,
        tunMode: tunMode ?? this.tunMode,
        tunStack: tunStack ?? this.tunStack,
        bypassLan: bypassLan ?? this.bypassLan,
        blockAds: blockAds ?? this.blockAds,
        ipv6: ipv6 ?? this.ipv6,
        dnsRemote: dnsRemote ?? this.dnsRemote,
        dnsDirect: dnsDirect ?? this.dnsDirect,
        autoConnect: autoConnect ?? this.autoConnect,
        killSwitch: killSwitch ?? this.killSwitch,
        activeNodeId:
            clearActiveNode ? null : (activeNodeId ?? this.activeNodeId),
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
      );

  Map<String, dynamic> toJson() => {
        'routingMode': routingMode.name,
        'perAppMode': perAppMode.name,
        'perAppSelected': perAppSelected.toList(),
        'triggerApps': triggerApps.toList(),
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
        perAppSelected:
            ((j['perAppSelected'] as List?)?.cast<String>() ?? const []).toSet(),
        triggerApps:
            ((j['triggerApps'] as List?)?.cast<String>() ?? const []).toSet(),
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

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}
