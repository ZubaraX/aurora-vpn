import 'package:aurora/data/models/enums.dart';
import 'package:aurora/data/models/vpn_settings.dart';
import 'package:aurora/data/parsers/subscription_parser.dart';
import 'package:aurora/engine/singbox_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = SubscriptionParser();

  group('SubscriptionParser', () {
    test('parses a VLESS Reality link', () {
      const link =
          'vless://11111111-2222-3333-4444-555555555555@example.com:443?'
          'security=reality&sni=www.microsoft.com&fp=chrome&pbk=abc&sid=00&'
          'type=grpc&serviceName=grpc&flow=xtls-rprx-vision#Node%20A';
      final node = parser.parseLink(link);
      expect(node, isNotNull);
      expect(node!.protocol, ProxyProtocol.vless);
      expect(node.server, 'example.com');
      expect(node.port, 443);
      expect(node.name, 'Node A');
      expect(node.params['pbk'], 'abc');
    });

    test('parses a Shadowsocks base64 userinfo link', () {
      // base64('aes-256-gcm:secretpass') = YWVzLTI1Ni1nY206c2VjcmV0cGFzcw==
      const link =
          'ss://YWVzLTI1Ni1nY206c2VjcmV0cGFzcw==@1.2.3.4:8388#SS%20Node';
      final node = parser.parseLink(link);
      expect(node, isNotNull);
      expect(node!.protocol, ProxyProtocol.shadowsocks);
      expect(node.params['method'], 'aes-256-gcm');
      expect(node.params['password'], 'secretpass');
      expect(node.port, 8388);
    });

    test('parses a Hysteria2 link', () {
      const link = 'hy2://pass@h2.example.com:443?sni=example.com&insecure=1#H2';
      final node = parser.parseLink(link);
      expect(node, isNotNull);
      expect(node!.protocol, ProxyProtocol.hysteria2);
      expect(node.params['insecure'], true);
    });

    test('decodes a base64-wrapped subscription of multiple links', () {
      const inner =
          'vless://uuid@a.com:443?security=tls&sni=a.com#A\n'
          'trojan://pw@b.com:443?sni=b.com#B';
      // base64 of the two-line blob.
      final b64 = _b64(inner);
      final nodes = parser.parseContent(b64, subscriptionId: 'sub1');
      expect(nodes.length, 2);
      expect(nodes.every((n) => n.subscriptionId == 'sub1'), isTrue);
    });
  });

  group('SingBoxConfigBuilder', () {
    test('emits per-app include_package on Android allowlist', () {
      final node = parser.parseLink('vless://uuid@a.com:443?security=tls&sni=a.com#A')!;
      const settings = VpnSettings(
        perAppMode: PerAppMode.allowlist,
        perAppSelected: {'org.telegram.messenger'},
      );
      final cfg = const SingBoxConfigBuilder(isAndroid: true).build(node, settings);
      final tun = (cfg['inbounds'] as List).first as Map;
      expect(tun['include_package'], contains('org.telegram.messenger'));
    });

    test('emits process_name route rule on Windows allowlist', () {
      final node = parser.parseLink('vless://uuid@a.com:443?security=tls&sni=a.com#A')!;
      const settings = VpnSettings(
        perAppMode: PerAppMode.allowlist,
        perAppSelected: {r'C:\Apps\Telegram.exe'},
      );
      final cfg = const SingBoxConfigBuilder(isAndroid: false).build(node, settings);
      final route = cfg['route'] as Map;
      final rules = route['rules'] as List;
      final hasProc = rules.any((r) =>
          r is Map && r['process_name'] is List && (r['process_name'] as List).contains('Telegram.exe'));
      expect(hasProc, isTrue);
      // Allow-list must default everything else to direct — otherwise the whole
      // system stays tunnelled and split tunnelling does nothing.
      expect(route['final'], 'direct');
    });
  });
}

String _b64(String s) {
  // Local helper mirroring a server-side base64 subscription payload.
  final bytes = s.codeUnits;
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final buffer = StringBuffer();
  for (var i = 0; i < bytes.length; i += 3) {
    final b0 = bytes[i];
    final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    buffer.write(chars[b0 >> 2]);
    buffer.write(chars[((b0 & 3) << 4) | (b1 >> 4)]);
    buffer.write(i + 1 < bytes.length ? chars[((b1 & 15) << 2) | (b2 >> 6)] : '=');
    buffer.write(i + 2 < bytes.length ? chars[b2 & 63] : '=');
  }
  return buffer.toString();
}
