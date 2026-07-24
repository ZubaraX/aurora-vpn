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

  Future<void> start(ProxyNode node, VpnSettings settings);
  Future<void> stop();

  /// Verifies that the selected outbound can carry an HTTPS request.
  Future<bool> verifyConnection();

  void dispose();
}
