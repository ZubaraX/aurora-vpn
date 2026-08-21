import 'package:flutter/material.dart';

import 'enums.dart';

/// Default resolver for direct (untunnelled) lookups: PLAIN UDP on port 53.
/// White-list networks refuse DoH on :443, so an encrypted default made every
/// direct lookup fail; plain DNS is what reference clients (Happ) use here.
const String kDefaultDirectDns = '8.8.8.8';

/// The encrypted default shipped before — migrated to [kDefaultDirectDns] on
/// load, since it is unusable on restricted networks.
const String kLegacyDirectDns = 'https://1.1.1.1/dns-query';

/// Sentinel trigger-app profile meaning "keep the VPN OFF on this network".
/// Lets a trigger use the tunnel on one network type but not the other.
const String kTriggerNoVpn = '__novpn__';

/// All persisted user preferences plus the currently selected node.
class VpnSettings {
  const VpnSettings({
    this.routingMode = RoutingMode.rule,
    this.perAppMode = PerAppMode.off,
    this.perAppSelected = const {},
    this.bypassPackages = const {},
    this.processProfiles = const {},
    this.collapsedSubs = const {},
    this.domainZoneRules = const {},
    this.triggerApps = const {},
    this.triggerWifiProfiles = const {},
    this.triggerMobileProfiles = const <String, List<String>>{},
    this.tunMode = true,
    this.tunStack = TunStack.mixed,
    this.bypassLan = true,
    this.blockAds = false,
    this.lanProxy = false,
    this.lanProxyPort = 2080,
    this.ipv6 = false,
    this.dnsRemote = 'https://1.1.1.1/dns-query',
    this.dnsDirect = kDefaultDirectDns,
    this.autoConnect = false,
    this.killSwitch = true,
    this.activeNodeId,
    this.themeMode = ThemeMode.dark,
    this.locale = 'ru',
  });

  final RoutingMode routingMode;
  final PerAppMode perAppMode;
  final Set<String> perAppSelected;

  /// Packages that must bypass the tunnel while it stays up. Used by trigger
  /// apps set to "Без VPN": that app goes direct, everyone else keeps the VPN,
  /// instead of tearing the whole tunnel down.
  final Set<String> bypassPackages;

  /// Desktop per-process routing: process/exe id → target. The target is a node
  /// id (route that process through that specific server) or [kTriggerNoVpn]
  /// (send it around the tunnel); an absent process follows the global routing
  /// mode. Emitted as `process_name` route rules on Windows.
  final Map<String, String> processProfiles;

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

  /// Exposes a SOCKS5/HTTP proxy on the local network so devices connected to
  /// this machine's hotspot can reach the internet through the tunnel.
  ///
  /// Android deliberately keeps tethered traffic out of a VpnService — it is
  /// forwarded in the kernel and never passes through our TUN — so on a
  /// non-rooted phone this proxy is the only way to share the VPN. Clients set
  /// the hotspot gateway address and [lanProxyPort] as their proxy by hand.
  final bool lanProxy;
  final int lanProxyPort;
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
    Set<String>? bypassPackages,
    Map<String, String>? processProfiles,
    Set<String>? collapsedSubs,
    Map<String, String>? domainZoneRules,
    Map<String, String>? triggerApps,
    Map<String, String>? triggerWifiProfiles,
    Map<String, List<String>>? triggerMobileProfiles,
    bool? tunMode,
    TunStack? tunStack,
    bool? bypassLan,
    bool? blockAds,
    bool? lanProxy,
    int? lanProxyPort,
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
    bypassPackages: bypassPackages ?? this.bypassPackages,
    processProfiles: processProfiles ?? this.processProfiles,
    collapsedSubs: collapsedSubs ?? this.collapsedSubs,
    domainZoneRules: domainZoneRules ?? this.domainZoneRules,
    triggerApps: triggerApps ?? this.triggerApps,
    triggerWifiProfiles: triggerWifiProfiles ?? this.triggerWifiProfiles,
    triggerMobileProfiles: triggerMobileProfiles ?? this.triggerMobileProfiles,
    tunMode: tunMode ?? this.tunMode,
    tunStack: tunStack ?? this.tunStack,
    bypassLan: bypassLan ?? this.bypassLan,
    blockAds: blockAds ?? this.blockAds,
    lanProxy: lanProxy ?? this.lanProxy,
    lanProxyPort: lanProxyPort ?? this.lanProxyPort,
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
    'bypassPackages': bypassPackages.toList(),
    'processProfiles': processProfiles,
    'collapsedSubs': collapsedSubs.toList(),
    'domainZoneRules': domainZoneRules,
    'triggerApps': triggerApps,
    'triggerWifiProfiles': triggerWifiProfiles,
    'triggerMobileProfiles': triggerMobileProfiles,
    'tunMode': tunMode,
    'tunStack': tunStack.name,
    'bypassLan': bypassLan,
    'blockAds': blockAds,
    'lanProxy': lanProxy,
    'lanProxyPort': lanProxyPort,
    'ipv6': ipv6,
    'dnsRemote': dnsRemote,
    'dnsDirect': dnsDirect,
    'autoConnect': autoConnect,
    'killSwitch': killSwitch,
    'activeNodeId': activeNodeId,
    'themeMode': themeMode.name,
    'locale': locale,
  };

  /// Tolerant parser: every field is read defensively so a single unexpected
  /// type can NEVER throw. A throw here would send SettingsController._load to
  /// blank defaults, and the next write would persist that — silently wiping
  /// trigger profiles / zone rules / the active selection.
  factory VpnSettings.fromJson(Map<String, dynamic> j) => VpnSettings(
    routingMode: _enum(RoutingMode.values, j['routingMode'], RoutingMode.rule),
    perAppMode: _enum(PerAppMode.values, j['perAppMode'], PerAppMode.off),
    perAppSelected: _stringList(j['perAppSelected']).toSet(),
    bypassPackages: _stringList(j['bypassPackages']).toSet(),
    processProfiles: _stringMap(
      j['processProfiles'],
    ).map((k, v) => MapEntry(k, _migTarget(v))),
    collapsedSubs: _stringList(j['collapsedSubs']).toSet(),
    domainZoneRules: _migValues(_stringMap(j['domainZoneRules'])),
    triggerApps: _migValues(_stringMap(j['triggerApps'])),
    triggerWifiProfiles: _migValues(_stringMap(j['triggerWifiProfiles'])),
    triggerMobileProfiles: _mobileProfiles(
      j['triggerMobileProfiles'],
    ).map((k, v) => MapEntry(k, v.map(_migTarget).toList())),
    tunMode: _bool(j['tunMode'], true),
    tunStack: _enum(TunStack.values, j['tunStack'], TunStack.mixed),
    bypassLan: _bool(j['bypassLan'], true),
    blockAds: _bool(j['blockAds'], false),
    lanProxy: _bool(j['lanProxy'], false),
    lanProxyPort: _port(j['lanProxyPort'], 2080),
    ipv6: _bool(j['ipv6'], false),
    dnsRemote: _str(j['dnsRemote'], 'https://1.1.1.1/dns-query'),
    // Migrate the old encrypted direct resolver: on white-list networks it is
    // refused (DoH :443), which broke every direct lookup.
    dnsDirect: switch (_str(j['dnsDirect'], kDefaultDirectDns)) {
      kLegacyDirectDns || '' => kDefaultDirectDns,
      final v => v,
    },
    autoConnect: _bool(j['autoConnect'], false),
    killSwitch: _bool(j['killSwitch'], true),
    activeNodeId: j['activeNodeId'] == null
        ? null
        : migrateNodeId('${j['activeNodeId']}'),
    themeMode: _enum(ThemeMode.values, j['themeMode'], ThemeMode.dark),
    locale: _str(j['locale'], 'ru'),
  );

  static List<String> _stringList(Object? raw) =>
      raw is List ? [for (final e in raw) '$e'] : const [];

  static bool _bool(Object? raw, bool fallback) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) return raw == 'true' || raw == '1';
    return fallback;
  }

  /// A listening port, clamped to the usable non-privileged range so a bad
  /// stored value can never produce a config the core refuses to start.
  static int _port(Object? raw, int fallback) {
    final v = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (v == null || v < 1024 || v > 65535) return fallback;
    return v;
  }

  static String _str(Object? raw, String fallback) =>
      raw is String ? raw : (raw == null ? fallback : '$raw');

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

  /// Migrates a routing target, preserving the [kTriggerNoVpn] sentinel — it
  /// contains underscores, so a blind [migrateNodeId] would mangle it.
  static String _migTarget(String v) =>
      v == kTriggerNoVpn ? v : migrateNodeId(v);

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
