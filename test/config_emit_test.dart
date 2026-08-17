// Emits representative sing-box configurations so CI can validate them with
// `sing-box check`. Unit tests only assert the JSON we *intend* to produce;
// this catches configs the core itself would reject — the class of bug that
// twice shipped a broken DNS setup.
//
// Runs as a test because the config builder reaches into Flutter (bundled geo
// assets), so a plain `dart run` cannot load it.
import 'dart:convert';
import 'dart:io';

import 'package:aurora/data/models/enums.dart';
import 'package:aurora/data/models/vpn_settings.dart';
import 'package:aurora/data/parsers/subscription_parser.dart';
import 'package:aurora/engine/singbox_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emit representative configs for sing-box check', () {
    final outPath =
        Platform.environment['AURORA_CONFIG_OUT'] ?? 'build/configs';

    final outDir = Directory(outPath)..createSync(recursive: true);
    const parser = SubscriptionParser();

    final reality = parser.parseLink(
      'vless://11111111-2222-3333-4444-555555555555@example.com:443'
      // A real x25519 public key: `sing-box check` rejects a placeholder, so the
      // emitted configs could never be validated with a fake one.
      '?security=reality&sni=www.microsoft.com&fp=chrome'
      '&pbk=Vzs5NxdN4ANBPvPX6wJwIu1CnwJUFHrfxPDEfCHPi1o&sid=00'
      '&type=tcp&flow=xtls-rprx-vision#Reality',
    )!;
    final ws = parser.parseLink(
      'vless://11111111-2222-3333-4444-555555555555@example.com:443'
      '?security=tls&sni=a.com&type=ws&path=/p&host=a.com#WS',
      subscriptionId: 'sub1',
    )!;
    final hy2 = parser.parseLink(
      'hy2://pw@h2.example.com:443?sni=h2.example.com#H2',
    )!;

    const zones = {
      'ru': 'direct',
      'рф': 'direct',
      'youtube.com': 'proxy',
      'ads.example': 'block',
    };

    void emit(
      String name,
      dynamic node,
      VpnSettings s, {
      List<dynamic> nodes = const [],
    }) {
      for (final android in [true, false]) {
        final cfg = SingBoxConfigBuilder(
          isAndroid: android,
        ).buildString(node, s, nodes: nodes.cast());
        File(
          '${outDir.path}/${name}_${android ? 'android' : 'windows'}.json',
        ).writeAsStringSync(cfg);
      }
    }

    emit('rule_default', reality, const VpnSettings());
    emit('global', reality, const VpnSettings(routingMode: RoutingMode.global));
    emit('direct', reality, const VpnSettings(routingMode: RoutingMode.direct));
    emit('zones', reality, const VpnSettings(domainZoneRules: zones));
    emit(
      'zone_server',
      reality,
      VpnSettings(domainZoneRules: {'ru': ws.id}),
      nodes: [ws],
    );
    emit(
      'perapp_allow',
      reality,
      const VpnSettings(
        perAppMode: PerAppMode.allowlist,
        perAppSelected: {'org.telegram.messenger'},
      ),
    );
    emit(
      'perapp_block',
      reality,
      const VpnSettings(
        perAppMode: PerAppMode.blocklist,
        perAppSelected: {'org.telegram.messenger'},
      ),
    );
    // Desktop per-process profiles: one process through a specific server, one
    // "Без VPN"; unassigned traffic follows the (direct) routing mode.
    emit(
      'proc_profiles',
      reality,
      VpnSettings(
        routingMode: RoutingMode.direct,
        processProfiles: {
          r'C:\Games\game.exe': kTriggerNoVpn,
          r'C:\Apps\chrome.exe': ws.id,
        },
      ),
      nodes: [ws],
    );
    emit('ads_ipv6', reality, const VpnSettings(blockAds: true, ipv6: true));
    emit('hysteria2', hy2, const VpnSettings());
    emit('ws', ws, const VpnSettings(tunStack: TunStack.gvisor));

    final count = outDir.listSync().whereType<File>().length;
    stdout.writeln('emitted $count configs to ${outDir.path}');
    // Fail loudly if a config is not even valid JSON.
    for (final f in outDir.listSync().whereType<File>()) {
      jsonDecode(f.readAsStringSync());
    }
  });
}
