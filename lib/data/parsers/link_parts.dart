import 'dart:convert';

/// Tolerant decomposition of a `scheme://[user@]host:port?query#fragment`
/// share link. Uri.parse chokes on some real-world links (raw fragments,
/// unescaped chars), so we split by hand.
class LinkParts {
  LinkParts({
    required this.scheme,
    required this.userinfo,
    required this.host,
    required this.port,
    required this.query,
    required this.fragment,
  });

  final String scheme;
  final String userinfo;
  final String host;
  final int port;
  final Map<String, String> query;
  final String fragment; // decoded #name

  String q(String key, [String fallback = '']) => query[key] ?? fallback;

  static LinkParts? parse(String link) {
    final schemeIdx = link.indexOf('://');
    if (schemeIdx < 0) return null;
    final scheme = link.substring(0, schemeIdx).toLowerCase();
    var rest = link.substring(schemeIdx + 3);

    // Fragment (#name).
    var fragment = '';
    final hashIdx = rest.indexOf('#');
    if (hashIdx >= 0) {
      fragment = _decode(rest.substring(hashIdx + 1));
      rest = rest.substring(0, hashIdx);
    }

    // Query (?a=b&c=d).
    final query = <String, String>{};
    final qIdx = rest.indexOf('?');
    if (qIdx >= 0) {
      final qs = rest.substring(qIdx + 1);
      rest = rest.substring(0, qIdx);
      for (final pair in qs.split('&')) {
        if (pair.isEmpty) continue;
        final eq = pair.indexOf('=');
        if (eq < 0) {
          query[pair] = '';
        } else {
          query[pair.substring(0, eq)] = _decode(pair.substring(eq + 1));
        }
      }
    }

    // Authority: [userinfo@]host:port.
    var authority = rest;
    var userinfo = '';
    final atIdx = authority.lastIndexOf('@');
    if (atIdx >= 0) {
      userinfo = authority.substring(0, atIdx);
      authority = authority.substring(atIdx + 1);
    }

    String host;
    int port = 0;
    if (authority.startsWith('[')) {
      // IPv6 literal: [::1]:443
      final close = authority.indexOf(']');
      host = authority.substring(1, close);
      final tail = authority.substring(close + 1);
      if (tail.startsWith(':')) port = int.tryParse(tail.substring(1)) ?? 0;
    } else {
      final colon = authority.lastIndexOf(':');
      if (colon >= 0) {
        host = authority.substring(0, colon);
        port = int.tryParse(authority.substring(colon + 1)) ?? 0;
      } else {
        host = authority;
      }
    }
    if (host.isEmpty) return null;

    return LinkParts(
      scheme: scheme,
      userinfo: _decode(userinfo),
      host: host,
      port: port,
      query: query,
      fragment: fragment,
    );
  }

  static String _decode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }
}

/// Base64 helpers tolerant of url-safe alphabet and missing padding.
String? tryBase64(String input) {
  var s = input.trim().replaceAll('\n', '').replaceAll('\r', '');
  if (s.isEmpty) return null;
  s = s.replaceAll('-', '+').replaceAll('_', '/');
  final pad = s.length % 4;
  if (pad > 0) s = s.padRight(s.length + (4 - pad), '=');
  try {
    return utf8.decode(base64.decode(s), allowMalformed: true);
  } catch (_) {
    return null;
  }
}
