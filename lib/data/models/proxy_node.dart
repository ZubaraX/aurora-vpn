import 'enums.dart';

/// A single proxy server parsed from a subscription or an individual share
/// link. Protocol-specific fields live in [params] so one model covers every
/// protocol; [toOutbound] turns it into a sing-box outbound object.
class ProxyNode {
  ProxyNode({
    required this.id,
    required this.name,
    required this.protocol,
    required this.server,
    required this.port,
    this.params = const {},
    this.subscriptionId,
    this.latencyMs,
  });

  final String id;
  final String name;
  final ProxyProtocol protocol;
  final String server;
  final int port;
  final Map<String, dynamic> params;

  /// Id of the owning subscription, or null for a manually added node.
  final String? subscriptionId;

  /// Last measured latency in ms; null = untested, -1 = unreachable.
  final int? latencyMs;

  String get subtitle => '${protocol.label} · $server:$port';

  /// Stable, position-independent identity used as the node [id]: a hash of the
  /// CONNECTION identity — protocol, server, port and every param (uuid, sni,
  /// network, path, flow, …). Two profiles that differ in any connection param
  /// get distinct ids even when they share a host; two that are identical
  /// connections collapse to one (they are interchangeable).
  ///
  /// The display [name] is deliberately EXCLUDED: providers often encode live
  /// data (remaining traffic, expiry) in the name, so hashing it would change a
  /// profile's id on every refresh and silently drop its saved selection. The
  /// id also ignores list position, so reordering never changes it.
  String get identityId {
    final keys = params.keys.toList()..sort();
    final p = keys.map((k) => '$k=${params[k]}').join('&');
    return '${protocol.name}|$server|$port|$p'.hashCode.toRadixString(16);
  }

  ProxyNode copyWith({String? id, int? latencyMs, String? subscriptionId}) => ProxyNode(
        id: id ?? this.id,
        name: name,
        protocol: protocol,
        server: server,
        port: port,
        params: params,
        subscriptionId: subscriptionId ?? this.subscriptionId,
        latencyMs: latencyMs ?? this.latencyMs,
      );

  // --- Persistence ---------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'server': server,
        'port': port,
        'params': params,
        'subscriptionId': subscriptionId,
        'latencyMs': latencyMs,
      };

  factory ProxyNode.fromJson(Map<String, dynamic> j) => ProxyNode(
        id: j['id'] as String,
        name: j['name'] as String,
        protocol: ProxyProtocol.values.byName(j['protocol'] as String),
        server: j['server'] as String,
        port: (j['port'] as num).toInt(),
        params: Map<String, dynamic>.from(j['params'] as Map? ?? const {}),
        subscriptionId: j['subscriptionId'] as String?,
        latencyMs: (j['latencyMs'] as num?)?.toInt(),
      );

  // --- sing-box outbound ---------------------------------------------------

  /// Builds a sing-box outbound object for this node under [tag].
  Map<String, dynamic> toOutbound(String tag) {
    final base = <String, dynamic>{
      'type': _singboxType,
      'tag': tag,
      'server': server,
      'server_port': port,
    };
    switch (protocol) {
      case ProxyProtocol.vless:
        base.addAll({
          'uuid': _s('uuid'),
          if (_has('flow')) 'flow': _s('flow'),
          'packet_encoding': 'xudp',
        });
        _attachTls(base);
        _attachTransport(base);
      case ProxyProtocol.vmess:
        base.addAll({
          'uuid': _s('uuid'),
          'security': _s('security', 'auto'),
          'alter_id': _i('alterId', 0),
        });
        _attachTls(base);
        _attachTransport(base);
      case ProxyProtocol.trojan:
        base['password'] = _s('password');
        _attachTls(base, defaultTls: true);
        _attachTransport(base);
      case ProxyProtocol.shadowsocks:
        base.addAll({
          'method': _s('method', 'aes-256-gcm'),
          'password': _s('password'),
        });
      case ProxyProtocol.hysteria2:
        base['password'] = _s('password');
        base['tls'] = _pruned({
          'enabled': true,
          'server_name': _s('sni', server),
          'insecure': _b('insecure'),
          'alpn': ['h3'],
        });
        if (_has('obfs')) {
          base['obfs'] = {'type': 'salamander', 'password': _s('obfsPassword')};
        }
        if (_has('up')) base['up_mbps'] = _i('up', 0);
        if (_has('down')) base['down_mbps'] = _i('down', 0);
      case ProxyProtocol.tuic:
        base.addAll({
          'uuid': _s('uuid'),
          'password': _s('password'),
          'congestion_control': _s('congestion', 'bbr'),
          'udp_relay_mode': _s('udpRelayMode', 'native'),
        });
        base['tls'] = _pruned({
          'enabled': true,
          'server_name': _s('sni', server),
          'insecure': _b('insecure'),
          'alpn': ['h3'],
        });
      case ProxyProtocol.wireguard:
        base.addAll({
          'local_address': (params['localAddress'] as List?)?.cast<String>() ??
              ['172.16.0.2/32'],
          'private_key': _s('privateKey'),
          'peer_public_key': _s('peerPublicKey'),
          if (_has('preSharedKey')) 'pre_shared_key': _s('preSharedKey'),
          if (_has('mtu')) 'mtu': _i('mtu', 1408),
          if (params['reserved'] is List) 'reserved': params['reserved'],
        });
      case ProxyProtocol.socks:
        base['version'] = '5';
        if (_has('username')) base['username'] = _s('username');
        if (_has('password')) base['password'] = _s('password');
      case ProxyProtocol.http:
        if (_has('username')) base['username'] = _s('username');
        if (_has('password')) base['password'] = _s('password');
        _attachTls(base);
    }
    return _pruned(base);
  }

  String get _singboxType => switch (protocol) {
        ProxyProtocol.vless => 'vless',
        ProxyProtocol.vmess => 'vmess',
        ProxyProtocol.trojan => 'trojan',
        ProxyProtocol.shadowsocks => 'shadowsocks',
        ProxyProtocol.hysteria2 => 'hysteria2',
        ProxyProtocol.tuic => 'tuic',
        ProxyProtocol.wireguard => 'wireguard',
        ProxyProtocol.socks => 'socks',
        ProxyProtocol.http => 'http',
      };

  void _attachTls(Map<String, dynamic> base, {bool defaultTls = false}) {
    final security = _s('security', defaultTls ? 'tls' : 'none');
    final enabled = security == 'tls' || security == 'reality' || _has('sni');
    if (!enabled) return;
    final tls = <String, dynamic>{
      'enabled': true,
      'server_name': _s('sni', server),
      'insecure': _b('insecure'),
      if (params['alpn'] is List && (params['alpn'] as List).isNotEmpty)
        'alpn': (params['alpn'] as List).cast<String>(),
      'utls': {
        'enabled': true,
        'fingerprint': _s('fp', 'chrome'),
      },
    };
    if (security == 'reality') {
      tls['reality'] = _pruned({
        'enabled': true,
        'public_key': _s('pbk'),
        'short_id': _s('sid'),
      });
    }
    base['tls'] = _pruned(tls);
  }

  void _attachTransport(Map<String, dynamic> base) {
    final net = _s('network', 'tcp');
    switch (net) {
      case 'ws':
        base['transport'] = _pruned({
          'type': 'ws',
          'path': _s('path', '/'),
          if (_has('host')) 'headers': {'Host': _s('host')},
        });
      case 'grpc':
        base['transport'] = {'type': 'grpc', 'service_name': _s('serviceName')};
      case 'http':
      case 'h2':
        base['transport'] = _pruned({
          'type': 'http',
          if (_has('host')) 'host': [_s('host')],
          'path': _s('path', '/'),
        });
      case 'httpupgrade':
        base['transport'] = _pruned({
          'type': 'httpupgrade',
          if (_has('host')) 'host': _s('host'),
          'path': _s('path', '/'),
        });
      default:
        break; // tcp — no transport block needed.
    }
  }

  // --- small typed accessors ----------------------------------------------

  bool _has(String k) {
    final v = params[k];
    return v != null && '$v'.isNotEmpty;
  }

  String _s(String k, [String fallback = '']) {
    final v = params[k];
    return (v == null || '$v'.isEmpty) ? fallback : '$v';
  }

  int _i(String k, int fallback) {
    final v = params[k];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  bool _b(String k) {
    final v = params[k];
    if (v is bool) return v;
    return v == 'true' || v == '1' || v == 1;
  }

  /// Drops null / empty-string / empty-map values recursively so the emitted
  /// sing-box JSON stays clean.
  static Map<String, dynamic> _pruned(Map<String, dynamic> m) {
    final out = <String, dynamic>{};
    m.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.isEmpty) return;
      if (v is Map) {
        final p = _pruned(Map<String, dynamic>.from(v));
        if (p.isNotEmpty) out[k] = p;
      } else {
        out[k] = v;
      }
    });
    return out;
  }
}
