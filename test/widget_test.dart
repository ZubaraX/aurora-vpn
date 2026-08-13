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

    test('node id is a stable identity hash, independent of subscription', () {
      // Saved trigger profiles / zone rules / active selection persist node
      // ids, so the same server must yield the same id across re-imports —
      // even under a different subscription. Only subscriptionId differs.
      const link = 'vless://uuid@a.com:443?security=tls&sni=a.com#A';
      final a = parser.parseContent(link, subscriptionId: 'subA');
      final b = parser.parseContent(link, subscriptionId: 'subB');
      expect(a.single.id, b.single.id);
      expect(a.single.subscriptionId, 'subA');
      expect(b.single.subscriptionId, 'subB');
    });

    test('node id ignores the display name but tracks connection params', () {
      // A provider changing a profile's label (traffic/expiry counters) must
      // NOT change its id, or the saved selection would drop on refresh…
      final renamed1 = parser.parseLink(
          'vless://uuid@a.com:443?security=tls&sni=a.com#Server%20%5B30GB%5D')!;
      final renamed2 = parser.parseLink(
          'vless://uuid@a.com:443?security=tls&sni=a.com#Server%20%5B29GB%5D')!;
      expect(renamed1.id, renamed2.id);
      // …but a real connection difference (SNI) still yields a distinct id.
      final otherSni = parser.parseLink(
          'vless://uuid@a.com:443?security=tls&sni=b.com#Server')!;
      expect(otherSni.id, isNot(renamed1.id));
    });

    test('an intercept/error page yields no nodes', () {
      // White-list networks answer the subscription URL with a portal page and
      // HTTP 200. It must parse to zero nodes — ProfileController._fetch relies
      // on that to detect the case and KEEP the stored servers instead of
      // wiping them (which would orphan every saved trigger profile).
      const page = '<!DOCTYPE html><html><body>Access denied</body></html>';
      expect(parser.parseContent(page, subscriptionId: 'sub1'), isEmpty);
      expect(parser.parseContent('', subscriptionId: 'sub1'), isEmpty);
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

    test('emits domain-zone rules (direct/proxy/block) with priority', () {
      final node =
          parser.parseLink('vless://uuid@a.com:443?security=tls&sni=a.com#A')!;
      const settings = VpnSettings(domainZoneRules: {
        'ru': 'direct',
        'com': 'proxy',
        'ads.example': 'block',
      });
      final cfg =
          const SingBoxConfigBuilder(isAndroid: true).build(node, settings);
      final rules = ((cfg['route'] as Map)['rules'] as List).cast<Map>();
      final direct = rules.firstWhere((r) =>
          r['outbound'] == 'direct' && r['domain_suffix'] is List &&
          (r['domain_suffix'] as List).contains('.ru'));
      expect(direct, isNotNull);
      final proxy = rules.firstWhere((r) =>
          r['outbound'] == 'proxy' && r['domain_suffix'] is List &&
          (r['domain_suffix'] as List).contains('.com'));
      expect(proxy, isNotNull);
      final block = rules.firstWhere((r) =>
          r['action'] == 'reject' && r['domain_suffix'] is List &&
          (r['domain_suffix'] as List).contains('.ads.example'));
      // An explicit host also matches its bare form.
      expect((block['domain_suffix'] as List), contains('ads.example'));
    });

    test('routes a domain zone through a specific server outbound', () {
      final active =
          parser.parseLink('vless://uuid@a.com:443?security=tls&sni=a.com#A')!;
      final other = parser.parseLink(
        'vless://uuid2@b.com:443?security=reality&sni=b.com&pbk=x&sid=00#B',
        subscriptionId: 'sub1',
      )!;
      final settings = VpnSettings(domainZoneRules: {'ru': other.id});
      final cfg = const SingBoxConfigBuilder(isAndroid: true)
          .build(active, settings, nodes: [other]);
      final outbounds = (cfg['outbounds'] as List).cast<Map>();
      expect(
        outbounds.any(
            (o) => o['tag'] == 'zone-${other.id}' && o['server'] == 'b.com'),
        isTrue,
      );
      final rules = ((cfg['route'] as Map)['rules'] as List).cast<Map>();
      expect(
        rules.any((r) =>
            r['outbound'] == 'zone-${other.id}' &&
            r['domain_suffix'] is List &&
            (r['domain_suffix'] as List).contains('.ru')),
        isTrue,
      );
    });

    test('domain zone with an unknown server id falls back to proxy', () {
      final active =
          parser.parseLink('vless://uuid@a.com:443?security=tls&sni=a.com#A')!;
      const settings = VpnSettings(domainZoneRules: {'ru': 'deleted-node'});
      final cfg = const SingBoxConfigBuilder(isAndroid: true)
          .build(active, settings, nodes: const []);
      final rules = ((cfg['route'] as Map)['rules'] as List).cast<Map>();
      expect(
        rules.any((r) =>
            r['outbound'] == 'proxy' &&
            r['domain_suffix'] is List &&
            (r['domain_suffix'] as List).contains('.ru')),
        isTrue,
      );
    });

    test('direct-routed zones also resolve via the direct DNS server', () {
      final node =
          parser.parseLink('vless://uuid@a.com:443?security=tls&sni=a.com#A')!;
      const settings = VpnSettings(domainZoneRules: {
        'ru': 'direct',
        'youtube.com': 'proxy',
      });
      final cfg =
          const SingBoxConfigBuilder(isAndroid: true).build(node, settings);
      final dnsRules = ((cfg['dns'] as Map)['rules'] as List).cast<Map>();
      final direct = dnsRules.firstWhere(
        (r) => r['server'] == 'direct' && r['domain_suffix'] is List,
        orElse: () => const {},
      );
      expect(direct['domain_suffix'], contains('.ru'));
      // Proxied zones must NOT be pinned to the direct resolver.
      expect(
        dnsRules.any((r) =>
            r['server'] == 'direct' &&
            r['domain_suffix'] is List &&
            (r['domain_suffix'] as List).contains('.youtube.com')),
        isFalse,
      );
    });

    test('converts an IDN zone to punycode (рф → xn--p1ai)', () {
      final node =
          parser.parseLink('vless://uuid@a.com:443?security=tls&sni=a.com#A')!;
      const settings = VpnSettings(domainZoneRules: {'рф': 'direct'});
      final cfg =
          const SingBoxConfigBuilder(isAndroid: true).build(node, settings);
      final rules = ((cfg['route'] as Map)['rules'] as List).cast<Map>();
      final direct = rules.firstWhere(
          (r) => r['outbound'] == 'direct' && r['domain_suffix'] is List);
      expect((direct['domain_suffix'] as List), contains('.xn--p1ai'));
    });

    test('rule-sets download through the proxy (white-list networks)', () {
      final node =
          parser.parseLink('vless://uuid@a.com:443?security=tls&sni=a.com#A')!;
      final cfg = const SingBoxConfigBuilder(isAndroid: true)
          .build(node, const VpnSettings());
      final ruleSets = (cfg['route'] as Map)['rule_set'] as List;
      expect(ruleSets, isNotEmpty);
      expect(
        ruleSets.every((r) => (r as Map)['download_detour'] == 'proxy'),
        isTrue,
      );
    });

    test('resolution never depends on the tunnel (direct, plain UDP)', () {
      // A dead server must not take DNS down with it: every lookup defaults to
      // the direct plain-UDP resolver, which white-list networks permit and
      // which keeps working when the proxy is unreachable.
      final node =
          parser.parseLink('vless://uuid@host.example:443?security=tls&sni=a.com#A')!;
      final cfg = const SingBoxConfigBuilder(isAndroid: true)
          .build(node, const VpnSettings());
      final dns = cfg['dns'] as Map;
      expect(dns['final'], 'direct');
      final direct = (dns['servers'] as List)
          .cast<Map>()
          .firstWhere((s) => s['tag'] == 'direct');
      expect(direct['type'], 'udp');
      expect(direct['server'], kDefaultDirectDns);
      final route = cfg['route'] as Map;
      expect((route['default_domain_resolver'] as Map)['server'], 'direct');
      final proxy = (cfg['outbounds'] as List)
          .cast<Map>()
          .firstWhere((o) => o['tag'] == 'proxy');
      expect(proxy['domain_resolver'], 'direct');
    });

    test('uses valid raw GitHub URLs for remote rule-sets', () {
      final node =
          parser.parseLink('vless://uuid@a.com:443?security=tls&sni=a.com#A')!;
      final cfg = const SingBoxConfigBuilder(isAndroid: true)
          .build(node, const VpnSettings());
      final route = cfg['route'] as Map;
      final ruleSets = route['rule_set'] as List;
      final urls = ruleSets.map((rule) => (rule as Map)['url'] as String);
      expect(
        urls,
        everyElement(matches(
          r'^https://raw\.githubusercontent\.com/SagerNet/'
          r'[^/]+/rule-set/[^/]+\.srs$',
        )),
      );
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
