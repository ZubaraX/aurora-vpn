import 'dart:io';

import 'package:aurora/data/models/enums.dart';
import 'package:aurora/data/models/proxy_node.dart';
import 'package:aurora/data/models/vpn_settings.dart';
import 'package:aurora/engine/singbox_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes a real-world config (VLESS + Reality, global routing) to the temp dir
/// so it can be validated with `sing-box check` against the installed core.
void main() {
  test('writes a sing-box config for external validation', () {
    final node = ProxyNode(
      id: 'de',
      name: '🇩🇪 Germany',
      protocol: ProxyProtocol.vless,
      server: 'de1.goarzain.top',
      port: 443,
      params: {
        'uuid': '16bc1346-756f-4f5f-a9e4-3360f32929ea',
        'security': 'reality',
        'sni': 'de1.goarzain.top',
        'fp': 'qq',
        'pbk': 'ipGPPjckDJXsORUElPV1Z28Gr3SsD6895o1Iubzi0ks',
        'sid': '2264330dcbb05f88',
        'flow': 'xtls-rprx-vision',
        'network': 'tcp',
      },
    );
    const settings = VpnSettings(routingMode: RoutingMode.global);
    final cfg =
        const SingBoxConfigBuilder(isAndroid: false).buildString(node, settings);

    final path = '${Directory.systemTemp.path}${Platform.pathSeparator}aurora_gen_config.json';
    File(path).writeAsStringSync(cfg);
    stdout.writeln('WROTE_CONFIG: $path');

    expect(cfg.contains('"type": "https"'), isTrue);
    expect(cfg.contains('legacy'), isFalse);
  });
}
