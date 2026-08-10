import 'package:aurora/data/models/proxy_node.dart';
import 'package:aurora/data/parsers/subscription_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = SubscriptionParser();

  const links = [
    'vless://11111111-2222-3333-4444-555555555555@a.com:443?security=reality&sni=www.microsoft.com&fp=chrome&pbk=abc&sid=00&type=tcp&flow=xtls-rprx-vision#Node',
    'vmess://eyJ2IjoiMiIsInBzIjoiTiIsImFkZCI6ImIuY29tIiwicG9ydCI6IjQ0MyIsImlkIjoidXVpZCIsImFpZCI6IjAiLCJuZXQiOiJ3cyIsInRscyI6InRscyIsImhvc3QiOiJoLmNvbSIsInBhdGgiOiIvcCIsInNuaSI6InMuY29tIiwiYWxwbiI6ImgyLGh0dHAvMS4xIn0=',
    'trojan://pass@c.com:443?sni=c.com&type=grpc&serviceName=svc#T',
    'hy2://pw@d.com:443?sni=d.com&insecure=1&obfs=salamander&obfs-password=x#H',
    'ss://YWVzLTI1Ni1nY206c2VjcmV0@e.com:8388#S',
  ];

  test('identityId is stable across a JSON store→load round-trip', () {
    for (final link in links) {
      final fresh = parser.parseLink(link, subscriptionId: 'sub1');
      expect(fresh, isNotNull, reason: link);
      final reloaded = ProxyNode.fromJson(fresh!.toJson());
      expect(
        reloaded.identityId,
        fresh.identityId,
        reason: 'round-trip changed identityId for: $link',
      );
      // And the persisted id itself must survive the round-trip.
      expect(reloaded.id, fresh.id, reason: link);
    }
  });

  test('a freshly parsed node keeps the same identityId on re-parse', () {
    for (final link in links) {
      final a = parser.parseLink(link, subscriptionId: 'subA');
      final b = parser.parseLink(link, subscriptionId: 'subB');
      expect(a!.identityId, b!.identityId, reason: link);
      expect(a.id, b.id, reason: link);
    }
  });
}
