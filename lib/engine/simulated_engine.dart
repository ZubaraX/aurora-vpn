import 'dart:async';
import 'dart:math';

import '../data/models/connection_stats.dart';
import '../data/models/enums.dart';
import '../data/models/proxy_node.dart';
import '../data/models/vpn_settings.dart';
import 'vpn_engine.dart';

/// A believable tunnel simulation used when no real sing-box core is available.
///
/// It runs the full state machine (connecting → connected → disconnecting) and
/// emits plausible throughput so every screen — the Aurora orb, live speed,
/// session timer, data counters — behaves exactly as it will against a real
/// core. Swapping in [WindowsProcessEngine] or the Android bridge changes
/// nothing above this layer.
class SimulatedEngine extends VpnEngine {
  final _statusCtrl = StreamController<ConnectionStatus>.broadcast();
  final _statsCtrl = StreamController<ConnectionStats>.broadcast();
  final _rng = Random();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStats _stats = ConnectionStats.empty;
  Timer? _ticker;
  Timer? _transition;

  @override
  Stream<ConnectionStatus> get statusStream => _statusCtrl.stream;

  @override
  Stream<ConnectionStats> get statsStream => _statsCtrl.stream;

  @override
  ConnectionStatus get status => _status;

  @override
  bool get isRealCore => false;

  @override
  String get backendLabel => 'Симуляция (ядро sing-box не найдено)';

  @override
  String? get lastError => null;

  void _emit(ConnectionStatus s) {
    _status = s;
    _statusCtrl.add(s);
  }

  @override
  Future<void> start(
    ProxyNode node,
    VpnSettings settings, {
    List<ProxyNode> nodes = const [],
  }) async {
    _transition?.cancel();
    _emit(ConnectionStatus.connecting);
    // Simulate a handshake with jittered latency.
    _transition = Timer(Duration(milliseconds: 600 + _rng.nextInt(900)), () {
      _stats = ConnectionStats(connectedSince: DateTime.now());
      _statsCtrl.add(_stats);
      _emit(ConnectionStatus.connected);
      _startTicker();
    });
  }

  @override
  Future<void> stop() async {
    _transition?.cancel();
    _ticker?.cancel();
    _emit(ConnectionStatus.disconnecting);
    _transition = Timer(const Duration(milliseconds: 350), () {
      _stats = ConnectionStats.empty;
      _statsCtrl.add(_stats);
      _emit(ConnectionStatus.disconnected);
    });
  }

  @override
  Future<bool> verifyConnection({bool thorough = false}) async => true;

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      // Correlated random walk so speeds feel organic rather than jittery.
      final down = _drift(_stats.downloadSpeed, 240 * 1024, 12 * 1024 * 1024);
      final up = _drift(_stats.uploadSpeed, 40 * 1024, 2 * 1024 * 1024);
      _stats = _stats.copyWith(
        downloadSpeed: down,
        uploadSpeed: up,
        downloadTotal: _stats.downloadTotal + down.round(),
        uploadTotal: _stats.uploadTotal + up.round(),
      );
      _statsCtrl.add(_stats);
    });
  }

  double _drift(double current, double floor, double ceil) {
    if (current <= 0) {
      current = floor + _rng.nextDouble() * (ceil - floor) * 0.3;
    }
    final step = (_rng.nextDouble() - 0.45) * ceil * 0.25;
    return (current + step).clamp(floor, ceil);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _transition?.cancel();
    _statusCtrl.close();
    _statsCtrl.close();
  }
}
