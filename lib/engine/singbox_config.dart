import 'dart:convert';

import '../data/models/enums.dart';
import '../data/models/proxy_node.dart';
import '../data/models/vpn_settings.dart';

/// Builds a complete, valid sing-box configuration from the selected node and
/// user settings. The same generator serves both platforms; per-app routing is
/// emitted differently for Android (TUN `include/exclude_package`) and Windows
/// (route rules keyed on `process_name`).
class SingBoxConfigBuilder {
  const SingBoxConfigBuilder({required this.isAndroid});

  final bool isAndroid;

  static const _geoBase = 'https://raw.githubusercontent.com/SagerNet';

  Map<String, dynamic> build(ProxyNode node, VpnSettings s) {
    return {
      // Keep enough core diagnostics to explain a tunnel that is established
      // but cannot pass traffic. Logs remain app-private and can be cleared
      // from the diagnostics screen.
      'log': {'level': 'info', 'timestamp': true},
      'dns': _dns(s),
      'inbounds': [_tunInbound(s)],
      'outbounds': [
        node.toOutbound('proxy'),
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': _route(s),
      'experimental': {
        'cache_file': {'enabled': true},
        'clash_api': {'external_controller': '127.0.0.1:9090'},
      },
    };
  }

  String buildString(ProxyNode node, VpnSettings s) =>
      const JsonEncoder.withIndent('  ').convert(build(node, s));

  // --- DNS (sing-box 1.12+ typed server format) ----------------------------

  Map<String, dynamic> _dns(VpnSettings s) {
    final rules = <Map<String, dynamic>>[
      {'clash_mode': 'Direct', 'server': 'direct'},
      {'clash_mode': 'Global', 'server': 'remote'},
    ];
    if (s.routingMode == RoutingMode.rule) {
      rules.add({'rule_set': 'geosite-cn', 'server': 'direct'});
    }
    return {
      'servers': [
        _dnsServer('remote', s.dnsRemote, 'proxy'),
        // Bootstrap resolver: encrypted DoH reached *directly* (a route rule
        // pins its IP to the direct outbound). This resolves the proxy server's
        // own domain before the tunnel is up and — crucially on RU networks —
        // never touches the ISP/system resolver, which may be poisoned or
        // hijacked by a leftover TUN adapter.
        _dnsServer('direct', s.dnsDirect, null),
      ],
      'rules': rules,
      'final': 'remote',
    };
  }

  /// Converts a DNS URL (`https://1.1.1.1/dns-query`, `8.8.8.8`, `tls://…`)
  /// into a sing-box 1.12+ typed DNS server object. Using IP hosts avoids any
  /// recursive-resolution dependency for the server itself.
  Map<String, dynamic> _dnsServer(String tag, String url, String? detour) {
    final u = url.trim();
    final scheme = RegExp(
      r'^([a-zA-Z0-9]+)://',
    ).firstMatch(u)?.group(1)?.toLowerCase();
    if (scheme != null) {
      final uri = Uri.tryParse(u);
      final host = (uri?.host.isNotEmpty ?? false) ? uri!.host : u;
      final type = switch (scheme) {
        'https' => 'https',
        'h3' => 'h3',
        'tls' => 'tls',
        'quic' => 'quic',
        'tcp' => 'tcp',
        _ => 'udp',
      };
      return {
        'type': type,
        'tag': tag,
        'server': host,
        if (uri != null && uri.hasPort) 'server_port': uri.port,
        'detour': ?detour,
      };
    }
    return {'type': 'udp', 'tag': tag, 'server': u, 'detour': ?detour};
  }

  /// The bare host of a DNS URL, or null (used to pin the bootstrap DoH direct).
  String? _dnsHost(String url) {
    final u = url.trim();
    if (u.contains('://')) return Uri.tryParse(u)?.host;
    return u.isEmpty ? null : u;
  }

  // --- Inbound (TUN) -------------------------------------------------------

  Map<String, dynamic> _tunInbound(VpnSettings s) {
    final tun = <String, dynamic>{
      'type': 'tun',
      'tag': 'tun-in',
      'interface_name': 'aurora-tun',
      'address': s.ipv6
          ? ['172.19.0.1/30', 'fdfe:dcba:9876::1/126']
          : ['172.19.0.1/30'],
      'mtu': 9000,
      'auto_route': true,
      'strict_route': true,
      'stack': s.tunStack.name,
    };

    // Android exposes per-app routing directly on the TUN inbound.
    if (isAndroid &&
        s.perAppMode != PerAppMode.off &&
        s.perAppSelected.isNotEmpty) {
      final key = s.perAppMode == PerAppMode.allowlist
          ? 'include_package'
          : 'exclude_package';
      tun[key] = s.perAppSelected.toList();
    }
    return tun;
  }

  // --- Route ---------------------------------------------------------------

  Map<String, dynamic> _route(VpnSettings s) {
    final rules = <Map<String, dynamic>>[
      {'action': 'sniff'},
      {'protocol': 'dns', 'action': 'hijack-dns'},
    ];

    // Pin the bootstrap DoH resolver's IP to the direct outbound so it is
    // reachable before the tunnel exists and never loops back into the TUN.
    final bootstrapHost = _dnsHost(s.dnsDirect);
    if (bootstrapHost != null && _isIpv4(bootstrapHost)) {
      rules.add({
        'ip_cidr': ['$bootstrapHost/32'],
        'outbound': 'direct',
      });
    }

    // Windows per-app split tunnelling via process_name.
    if (!isAndroid &&
        s.perAppMode != PerAppMode.off &&
        s.perAppSelected.isNotEmpty) {
      final procs = s.perAppSelected.map(_exeName).toList();
      if (s.perAppMode == PerAppMode.allowlist) {
        // Only selected processes are tunnelled; everything else goes direct.
        rules.add({'process_name': procs, 'outbound': 'proxy'});
      } else {
        // Selected processes bypass the tunnel.
        rules.add({'process_name': procs, 'outbound': 'direct'});
      }
    }

    if (s.bypassLan) {
      rules.add({'ip_is_private': true, 'outbound': 'direct'});
    }
    // User domain-zone rules win over the default rule-set routing below.
    rules.addAll(_domainZoneRules(s));
    if (s.blockAds) {
      rules.add({'rule_set': 'geosite-ads', 'action': 'reject'});
    }
    if (s.routingMode == RoutingMode.rule) {
      rules.add({
        'rule_set': ['geosite-cn', 'geoip-cn'],
        'outbound': 'direct',
      });
    }
    rules.add({'clash_mode': 'Direct', 'outbound': 'direct'});
    rules.add({'clash_mode': 'Global', 'outbound': 'proxy'});

    // Default outbound. In Windows allow-list mode ("только выбранные") the
    // process_name rule already sends chosen apps to the proxy, so everything
    // else must default to direct — otherwise the whole system stays tunnelled
    // and split tunnelling does nothing.
    final winAllowlist =
        !isAndroid &&
        s.perAppMode == PerAppMode.allowlist &&
        s.perAppSelected.isNotEmpty;
    final String finalOutbound;
    if (winAllowlist || s.routingMode == RoutingMode.direct) {
      finalOutbound = 'direct';
    } else {
      finalOutbound = 'proxy';
    }

    final route = <String, dynamic>{
      'rules': rules,
      'final': finalOutbound,
      'auto_detect_interface': true,
      'default_domain_resolver': {
        'server': 'direct',
        'strategy': s.ipv6 ? 'prefer_ipv4' : 'ipv4_only',
      },
    };
    if (isAndroid) route['override_android_vpn'] = true;

    final ruleSets = _ruleSets(s);
    if (ruleSets.isNotEmpty) route['rule_set'] = ruleSets;
    return route;
  }

  /// Turns the user's domain-zone map into sing-box route rules, grouped by
  /// target. A zone `ru` becomes `domain_suffix: ".ru"` (matches every `*.ru`);
  /// an explicit host like `google.com` also matches the bare domain.
  List<Map<String, dynamic>> _domainZoneRules(VpnSettings s) {
    if (s.domainZoneRules.isEmpty) return const [];
    final direct = <String>[];
    final proxy = <String>[];
    final block = <String>[];
    s.domainZoneRules.forEach((zone, target) {
      final z = _toAsciiDomain(zone.trim().toLowerCase());
      if (z.isEmpty) return;
      final suffixes = z.contains('.') ? ['.$z', z] : ['.$z'];
      switch (target) {
        case 'direct':
          direct.addAll(suffixes);
        case 'block':
          block.addAll(suffixes);
        default:
          proxy.addAll(suffixes);
      }
    });
    final out = <Map<String, dynamic>>[];
    if (direct.isNotEmpty) out.add({'domain_suffix': direct, 'outbound': 'direct'});
    if (proxy.isNotEmpty) out.add({'domain_suffix': proxy, 'outbound': 'proxy'});
    if (block.isNotEmpty) out.add({'domain_suffix': block, 'action': 'reject'});
    return out;
  }

  List<Map<String, dynamic>> _ruleSets(VpnSettings s) {
    final sets = <Map<String, dynamic>>[];
    // Downloaded via the direct outbound so a rule-set fetch never depends on
    // the tunnel it is meant to configure (that deadlocks on first connect).
    void add(String tag, String repo, String file) => sets.add({
      'type': 'remote',
      'tag': tag,
      'format': 'binary',
      // `rule-set` is the branch name. raw.githubusercontent.com URLs
      // address it directly; inserting an extra `/raw/` returns 404 and
      // prevents the core from starting.
      'url': '$_geoBase/$repo/rule-set/$file.srs',
      'download_detour': 'direct',
    });
    if (s.blockAds) {
      add('geosite-ads', 'sing-geosite', 'geosite-category-ads-all');
    }
    if (s.routingMode == RoutingMode.rule) {
      add('geosite-cn', 'sing-geosite', 'geosite-cn');
      add('geoip-cn', 'sing-geoip', 'geoip-cn');
    }
    return sets;
  }

  /// `C:\Path\App.exe` → `App.exe`; a bare package/name is returned as-is.
  String _exeName(String id) {
    final normalized = id.replaceAll('\\', '/');
    final base = normalized.contains('/')
        ? normalized.split('/').last
        : normalized;
    return base;
  }

  /// Converts an internationalised domain (e.g. `сайт.рф`) to its ASCII/A-label
  /// form (`xn--80aswg.xn--p1ai`) so a `domain_suffix` rule matches the punycode
  /// SNI/DNS names sing-box actually sees. Pure-ASCII input is returned as-is.
  String _toAsciiDomain(String domain) {
    if (domain.codeUnits.every((c) => c < 0x80)) return domain;
    return domain.split('.').map((label) {
      if (label.isEmpty || label.runes.every((r) => r < 0x80)) return label;
      return 'xn--${_punycodeEncode(label)}';
    }).join('.');
  }

  /// RFC 3492 punycode encoder for a single label.
  String _punycodeEncode(String input) {
    const base = 36, tmin = 1, tmax = 26, skew = 38, damp = 700;
    const initialBias = 72, initialN = 128;
    final code = input.runes.toList();
    final output = StringBuffer();
    for (final c in code) {
      if (c < 0x80) output.writeCharCode(c);
    }
    var b = output.length;
    var h = b;
    if (b > 0) output.write('-');
    var n = initialN, delta = 0, bias = initialBias;
    String digit(int d) =>
        String.fromCharCode(d < 26 ? d + 0x61 : d - 26 + 0x30);
    int adapt(int d, int numPoints, bool first) {
      d = first ? d ~/ damp : d ~/ 2;
      d += d ~/ numPoints;
      var k = 0;
      while (d > ((base - tmin) * tmax) ~/ 2) {
        d ~/= (base - tmin);
        k += base;
      }
      return k + ((base - tmin + 1) * d) ~/ (d + skew);
    }

    while (h < code.length) {
      var m = 1 << 30;
      for (final c in code) {
        if (c >= n && c < m) m = c;
      }
      delta += (m - n) * (h + 1);
      n = m;
      for (final c in code) {
        if (c < n) delta++;
        if (c == n) {
          var q = delta;
          for (var k = base;; k += base) {
            final t = k <= bias ? tmin : (k >= bias + tmax ? tmax : k - bias);
            if (q < t) break;
            output.write(digit(t + (q - t) % (base - t)));
            q = (q - t) ~/ (base - t);
          }
          output.write(digit(q));
          bias = adapt(delta, h + 1, h == b);
          delta = 0;
          h++;
        }
      }
      delta++;
      n++;
    }
    return output.toString();
  }

  bool _isIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }
}
