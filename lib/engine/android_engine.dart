import 'dart:async';

import 'package:flutter/services.dart';

import '../data/models/connection_stats.dart';
import '../data/models/enums.dart';
import '../data/models/proxy_node.dart';
import '../data/models/vpn_settings.dart';
import 'singbox_config.dart';
import 'vpn_engine.dart';

/// Bridges to the native Android `VpnService` (see
/// android/app/src/main/kotlin/.../AuroraVpnService.kt). Dart generates the
/// sing-box config; the platform side hands it to the bundled libbox core and
/// owns the VpnService lifecycle and per-app allow/deny lists.
class AndroidVpnEngine implements VpnEngine {
  static const _method = MethodChannel('aurora/vpn');
  static const _statusEvents = EventChannel('aurora/vpn/status');
  static const _statsEvents = EventChannel('aurora/vpn/stats');

  final _statusCtrl = StreamController<ConnectionStatus>.broadcast();
  final _statsCtrl = StreamController<ConnectionStats>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  StreamSubscription? _statusSub;
  StreamSubscription? _statsSub;

  AndroidVpnEngine() {
    _statusSub = _statusEvents.receiveBroadcastStream().listen((e) {
      final s = ConnectionStatus.values
          .firstWhere((v) => v.name == '$e', orElse: () => _status);
      _status = s;
      _statusCtrl.add(s);
    }, onError: (_) {});
    _statsSub = _statsEvents.receiveBroadcastStream().listen((e) {
      if (e is Map) {
        _statsCtrl.add(ConnectionStats(
          uploadTotal: (e['uploadTotal'] as num?)?.toInt() ?? 0,
          downloadTotal: (e['downloadTotal'] as num?)?.toInt() ?? 0,
          uploadSpeed: (e['uploadSpeed'] as num?)?.toDouble() ?? 0,
          downloadSpeed: (e['downloadSpeed'] as num?)?.toDouble() ?? 0,
          connectedSince: e['connectedSince'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (e['connectedSince'] as num).toInt()),
        ));
      }
    }, onError: (_) {});
  }

  @override
  Stream<ConnectionStatus> get statusStream => _statusCtrl.stream;
  @override
  Stream<ConnectionStats> get statsStream => _statsCtrl.stream;
  @override
  ConnectionStatus get status => _status;
  @override
  bool get isRealCore => true;
  @override
  String get backendLabel => 'sing-box libbox · Android VpnService';

  @override
  String? get lastError =>
      'Ядро для Android (sing-box libbox) пока не встроено — туннель недоступен. '
      'Пользуйтесь Windows-версией; поддержка Android в разработке.';

  /// Probes whether the native side is wired up.
  static Future<bool> available() async {
    try {
      final ok = await _method.invokeMethod<bool>('ping');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start(ProxyNode node, VpnSettings settings) async {
    _status = ConnectionStatus.connecting;
    _statusCtrl.add(_status);
    final config =
        const SingBoxConfigBuilder(isAndroid: true).buildString(node, settings);
    await _method.invokeMethod('start', {
      'config': config,
      'perAppMode': settings.perAppMode.name,
      'perApp': settings.perAppSelected.toList(),
    });
  }

  @override
  Future<void> stop() async {
    _status = ConnectionStatus.disconnecting;
    _statusCtrl.add(_status);
    await _method.invokeMethod('stop');
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _statsSub?.cancel();
    _statusCtrl.close();
    _statsCtrl.close();
  }
}
