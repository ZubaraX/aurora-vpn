import 'dart:convert';

import '../models/enums.dart';
import '../models/proxy_node.dart';
import 'link_parts.dart';

/// Turns raw subscription content (or a single pasted link) into [ProxyNode]s.
///
/// Handles: base64-wrapped node lists, plain newline-separated links, and the
/// individual VLESS / VMess / Trojan / Shadowsocks / Hysteria2 / TUIC formats.
class SubscriptionParser {
  const SubscriptionParser();

  /// Parses a whole subscription payload into nodes.
  List<ProxyNode> parseContent(String raw, {String? subscriptionId}) {
    final text = _unwrap(raw).trim();
    final nodes = <ProxyNode>[];
    var index = 0;
    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final node = parseLink(trimmed, subscriptionId: subscriptionId, index: index);
      if (node != null) {
        nodes.add(node);
        index++;
      }
    }
    return nodes;
  }

  /// If the payload is a single base64 blob (no scheme present), decode it.
  String _unwrap(String raw) {
    if (raw.contains('://')) return raw;
    final decoded = tryBase64(raw);
    if (decoded != null && decoded.contains('://')) return decoded;
    return raw;
  }

  /// Parses one share link. Returns null for anything unrecognised.
  ProxyNode? parseLink(String link, {String? subscriptionId, int index = 0}) {
    try {
      final scheme = link.split('://').first.toLowerCase();
      final node = switch (scheme) {
        'vmess' => _vmess(link, index),
        'vless' => _fromParts(link, ProxyProtocol.vless, index),
        'trojan' => _fromParts(link, ProxyProtocol.trojan, index),
        'ss' => _shadowsocks(link, index),
        'hysteria2' || 'hy2' => _hysteria2(link, index),
        'tuic' => _tuic(link, index),
        _ => null,
      };
      // Node ids are a stable hash of the server identity (see `_id`) and are
      // deliberately NOT scoped to the subscription: trigger-app profiles,
      // domain-zone rules and the active selection all persist these ids, so
      // they must stay identical across restarts and re-imports. Scoping them
      // to the subscription once orphaned every saved selection ("узел удалён").
      return node?.copyWith(subscriptionId: subscriptionId);
    } catch (_) {
      return null;
    }
  }

  String _id(String seed, int index) =>
      '${seed.hashCode.toRadixString(16)}_$index';

  String _name(String? given, String fallback) =>
      (given == null || given.trim().isEmpty) ? fallback : given.trim();

  // --- VMess (base64 JSON) -------------------------------------------------

  ProxyNode? _vmess(String link, int index) {
    final body = link.substring('vmess://'.length);
    final json = tryBase64(body);
    if (json == null) return null;
    final m = jsonDecode(json) as Map<String, dynamic>;
    final server = '${m['add']}';
    final port = int.tryParse('${m['port']}') ?? 0;
    final net = '${m['net'] ?? 'tcp'}';
    final tls = '${m['tls'] ?? ''}' == 'tls';
    return ProxyNode(
      id: _id('$server$port${m['id']}', index),
      name: _name('${m['ps'] ?? ''}', '$server:$port'),
      protocol: ProxyProtocol.vmess,
      server: server,
      port: port,
      params: {
        'uuid': '${m['id']}',
        'alterId': int.tryParse('${m['aid'] ?? 0}') ?? 0,
        'security': '${m['scy'] ?? 'auto'}',
        'network': net,
        'path': '${m['path'] ?? ''}',
        'host': '${m['host'] ?? ''}',
        'serviceName': net == 'grpc' ? '${m['path'] ?? ''}' : '',
        if (tls) 'security': 'tls',
        'sni': '${m['sni'] ?? m['host'] ?? ''}',
        if ('${m['alpn'] ?? ''}'.isNotEmpty)
          'alpn': '${m['alpn']}'.split(','),
        'fp': '${m['fp'] ?? 'chrome'}',
      },
    );
  }

  // --- VLESS / Trojan (URI with query) ------------------------------------

  ProxyNode? _fromParts(String link, ProxyProtocol proto, int index) {
    final p = LinkParts.parse(link);
    if (p == null) return null;
    final net = p.q('type', 'tcp');
    final params = <String, dynamic>{
      if (proto == ProxyProtocol.vless) 'uuid': p.userinfo,
      if (proto == ProxyProtocol.trojan) 'password': p.userinfo,
      'security': p.q('security', proto == ProxyProtocol.trojan ? 'tls' : 'none'),
      'sni': p.q('sni', p.q('peer')),
      'fp': p.q('fp', 'chrome'),
      'pbk': p.q('pbk'),
      'sid': p.q('sid'),
      'flow': p.q('flow'),
      'network': net,
      'path': p.q('path'),
      'host': p.q('host'),
      'serviceName': p.q('serviceName', p.q('servicename')),
      'insecure': p.q('allowInsecure') == '1' || p.q('insecure') == '1',
      if (p.q('alpn').isNotEmpty) 'alpn': p.q('alpn').split(','),
    };
    return ProxyNode(
      id: _id('${p.host}${p.port}${p.userinfo}', index),
      name: _name(p.fragment, '${p.host}:${p.port}'),
      protocol: proto,
      server: p.host,
      port: p.port,
      params: params,
    );
  }

  // --- Shadowsocks ---------------------------------------------------------

  ProxyNode? _shadowsocks(String link, int index) {
    var body = link.substring('ss://'.length);
    String name = '';
    final hashIdx = body.indexOf('#');
    if (hashIdx >= 0) {
      name = Uri.decodeComponent(body.substring(hashIdx + 1));
      body = body.substring(0, hashIdx);
    }
    // Strip plugin query if present.
    final qIdx = body.indexOf('?');
    if (qIdx >= 0) body = body.substring(0, qIdx);

    String method, password, host;
    int port;
    final atIdx = body.lastIndexOf('@');
    if (atIdx >= 0) {
      // ss://base64(method:pass)@host:port  OR  ss://method:pass@host:port
      var userinfo = body.substring(0, atIdx);
      final hostport = body.substring(atIdx + 1);
      final decoded = tryBase64(userinfo);
      if (decoded != null && decoded.contains(':')) userinfo = decoded;
      final colon = userinfo.indexOf(':');
      method = userinfo.substring(0, colon);
      password = userinfo.substring(colon + 1);
      (host, port) = _hostPort(hostport);
    } else {
      // ss://base64(method:pass@host:port)
      final decoded = tryBase64(body);
      if (decoded == null) return null;
      final at = decoded.lastIndexOf('@');
      final userinfo = decoded.substring(0, at);
      final hostport = decoded.substring(at + 1);
      final colon = userinfo.indexOf(':');
      method = userinfo.substring(0, colon);
      password = userinfo.substring(colon + 1);
      (host, port) = _hostPort(hostport);
    }

    return ProxyNode(
      id: _id('$host$port$password', index),
      name: _name(name, '$host:$port'),
      protocol: ProxyProtocol.shadowsocks,
      server: host,
      port: port,
      params: {'method': method, 'password': password},
    );
  }

  // --- Hysteria2 -----------------------------------------------------------

  ProxyNode? _hysteria2(String link, int index) {
    final p = LinkParts.parse(link);
    if (p == null) return null;
    return ProxyNode(
      id: _id('${p.host}${p.port}${p.userinfo}', index),
      name: _name(p.fragment, '${p.host}:${p.port}'),
      protocol: ProxyProtocol.hysteria2,
      server: p.host,
      port: p.port,
      params: {
        'password': p.userinfo.isNotEmpty ? p.userinfo : p.q('password'),
        'sni': p.q('sni', p.q('peer')),
        'insecure': p.q('insecure') == '1' || p.q('allowInsecure') == '1',
        'obfs': p.q('obfs'),
        'obfsPassword': p.q('obfs-password'),
        if (p.q('up').isNotEmpty) 'up': int.tryParse(p.q('up')) ?? 0,
        if (p.q('down').isNotEmpty) 'down': int.tryParse(p.q('down')) ?? 0,
      },
    );
  }

  // --- TUIC ----------------------------------------------------------------

  ProxyNode? _tuic(String link, int index) {
    final p = LinkParts.parse(link);
    if (p == null) return null;
    final creds = p.userinfo.split(':');
    return ProxyNode(
      id: _id('${p.host}${p.port}${p.userinfo}', index),
      name: _name(p.fragment, '${p.host}:${p.port}'),
      protocol: ProxyProtocol.tuic,
      server: p.host,
      port: p.port,
      params: {
        'uuid': creds.isNotEmpty ? creds[0] : '',
        'password': creds.length > 1 ? creds.sublist(1).join(':') : '',
        'sni': p.q('sni', p.q('peer')),
        'congestion': p.q('congestion_control', 'bbr'),
        'udpRelayMode': p.q('udp_relay_mode', 'native'),
        'insecure': p.q('allow_insecure') == '1' || p.q('insecure') == '1',
        if (p.q('alpn').isNotEmpty) 'alpn': p.q('alpn').split(','),
      },
    );
  }

  (String, int) _hostPort(String s) {
    if (s.startsWith('[')) {
      final close = s.indexOf(']');
      final host = s.substring(1, close);
      final tail = s.substring(close + 1);
      final port = tail.startsWith(':') ? int.tryParse(tail.substring(1)) ?? 0 : 0;
      return (host, port);
    }
    final colon = s.lastIndexOf(':');
    if (colon < 0) return (s, 0);
    return (s.substring(0, colon), int.tryParse(s.substring(colon + 1)) ?? 0);
  }
}
