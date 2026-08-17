import 'dart:async';

import '../data/models/connection_stats.dart';
import '../data/models/enums.dart';
import '../data/models/proxy_node.dart';
import '../data/models/vpn_settings.dart';

/// Contract every tunnel backend implements. The rest of the app talks only to
/// this interface, so the Windows process core, the Android VpnService bridge
/// and the in-app simulation are interchangeable.
abstract class VpnEngine {
  Stream<ConnectionStatus> get statusStream;
  Stream<ConnectionStats> get statsStream;

  ConnectionStatus get status;

  /// True when a genuine sing-box core is driving the tunnel (as opposed to the
  /// built-in simulation used when no core binary is present).
  bool get isRealCore;

  /// Short human label describing the active backend (shown in Settings).
  String get backendLabel;

  /// Human-readable reason for the most recent failure, if any (surfaced when
  /// the status becomes [ConnectionStatus.error]).
  String? get lastError => null;

  /// Starts the tunnel on [node]. [nodes] is the full node list so domain-zone
  /// rules can route specific zones through other servers (extra outbounds).
  Future<void> start(
    ProxyNode node,
    VpnSettings settings, {
    List<ProxyNode> nodes = const [],
  });
  Future<void> stop();

  /// Replaces the active outbound with [node].
  ///
  /// Process-based engines need a full stop before starting the replacement.
  /// Android overrides this to use libbox's in-process reload, which keeps the
  /// single Clash controller alive and avoids racing a second listener on
  /// 127.0.0.1:9090.
  Future<void> replace(
    ProxyNode node,
    VpnSettings settings, {
    List<ProxyNode> nodes = const [],
  }) async {
    if (status.isActive) {
      await stop();
      if (status != ConnectionStatus.disconnected) {
        try {
          await statusStream
              .firstWhere(
                (value) =>
                    value == ConnectionStatus.disconnected ||
                    value == ConnectionStatus.error,
              )
              .timeout(const Duration(seconds: 10));
        } on TimeoutException {
          // Let start() surface a backend-specific error if shutdown stalled.
        }
      }
    }
    await start(node, settings, nodes: nodes);
  }

  /// Verifies that the selected outbound can carry an HTTPS request.
  ///
  /// [thorough] trades speed for certainty: a cold dial through a cellular exit
  /// routinely needs ~3s, so the quick screen used while picking a candidate
  /// would condemn working servers if it also decided the fate of a live
  /// tunnel. Watchdog callers pass true.
  Future<bool> verifyConnection({bool thorough = false});

  /// Whether a VPN interface actually exists right now.
  ///
  /// Reporting "connected" from our own bookkeeping alone hid a tunnel that
  /// Android had torn down underneath us (MIUI does this), leaving the app
  /// claiming protection while traffic went straight out. Backends that cannot
  /// tell report true so behaviour is unchanged.
  Future<bool> tunnelAlive() async => true;

  void dispose();
}
