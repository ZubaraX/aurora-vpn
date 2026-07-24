import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/local/app_paths.dart';
import '../data/models/connection_stats.dart';
import '../data/models/enums.dart';
import '../data/models/proxy_node.dart';
import '../data/models/vpn_settings.dart';
import 'singbox_config.dart';
import 'vpn_engine.dart';

/// Drives a real `sing-box.exe` process on Windows.
///
/// The generated config is written to the app data directory, sing-box is
/// launched with `run -c <config>`, and readiness is confirmed by polling the
/// Clash API it exposes on 127.0.0.1:9090 — the status stays `connecting` until
/// the core is genuinely up, so no spurious error flashes. Live throughput is
/// then read from the same API. Raising the TUN needs elevation and a free TUN
/// slot; conflicts (another VPN already holding one) surface as a clear
/// [lastError].
class WindowsProcessEngine implements VpnEngine {
  WindowsProcessEngine(this._corePath);

  final String _corePath;

  final _statusCtrl = StreamController<ConnectionStatus>.broadcast();
  final _statsCtrl = StreamController<ConnectionStats>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStats _stats = ConnectionStats.empty;
  Process? _process;
  Timer? _poller;
  int _lastUp = 0;
  int _lastDown = 0;
  String? _lastError;
  final _logTail = <String>[];

  @override
  Stream<ConnectionStatus> get statusStream => _statusCtrl.stream;
  @override
  Stream<ConnectionStats> get statsStream => _statsCtrl.stream;
  @override
  ConnectionStatus get status => _status;
  @override
  bool get isRealCore => true;
  @override
  String get backendLabel => 'sing-box core · Windows TUN';
  @override
  String? get lastError => _lastError;

  /// Captured sing-box stdout/stderr for the in-app Logs screen.
  String get logTail => _logTail.isEmpty
      ? 'Логи ядра появятся после подключения.'
      : _logTail.join('\n');

  void _emit(ConnectionStatus s) {
    _status = s;
    _statusCtrl.add(s);
  }

  static Future<String?> findCore() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$exeDir\\sing-box.exe',
      '$exeDir\\core\\sing-box.exe',
      'sing-box.exe',
    ];
    for (final c in candidates) {
      if (c == 'sing-box.exe') {
        try {
          final r = await Process.run('where', ['sing-box']);
          if (r.exitCode == 0) {
            final path = (r.stdout as String).trim().split('\n').first.trim();
            if (path.isNotEmpty) return path;
          }
        } catch (_) {}
      } else if (await File(c).exists()) {
        return c;
      }
    }
    return null;
  }

  @override
  Future<void> start(ProxyNode node, VpnSettings settings) async {
    _lastError = null;
    _logTail.clear();
    _emit(ConnectionStatus.connecting);
    try {
      await _killOwnCore();

      final config = const SingBoxConfigBuilder(isAndroid: false)
          .buildString(node, settings);
      final file = File('${AppPaths.dataDir().path}\\aurora-config.json');
      await file.writeAsString(config);

      var exited = false;
      _process = await Process.start(_corePath, ['run', '-c', file.path]);
      _process!.stderr.transform(utf8.decoder).listen(_capture);
      _process!.stdout.transform(utf8.decoder).listen(_capture);
      unawaited(_process!.exitCode.then((_) {
        exited = true;
        if (_status.isActive) {
          _lastError ??= _diagnose();
          _emit(ConnectionStatus.error);
        }
        _cleanup();
      }));

      // Poll for readiness rather than guessing with a fixed delay.
      final ready = await _waitReady(() => exited);
      if (ready) {
        _stats = ConnectionStats(connectedSince: DateTime.now());
        _statsCtrl.add(_stats);
        _emit(ConnectionStatus.connected);
        _startPolling();
      } else if (_status == ConnectionStatus.connecting) {
        _lastError = await _diagnoseAsync();
        _emit(ConnectionStatus.error);
        _cleanup();
      }
    } catch (e) {
      _lastError = 'Не удалось запустить ядро sing-box';
      _emit(ConnectionStatus.error);
      _cleanup();
    }
  }

  void _capture(String chunk) {
    for (final line in const LineSplitter().convert(chunk)) {
      if (line.trim().isEmpty) continue;
      _logTail.add(line);
      if (_logTail.length > 40) _logTail.removeAt(0);
    }
  }

  /// Waits up to ~12s for the Clash API to answer, bailing early if the core
  /// process dies. Returns true only when the core is genuinely up.
  Future<bool> _waitReady(bool Function() exited) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      if (exited()) return false;
      if (await _apiReachable()) return true;
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  Future<bool> _apiReachable() async {
    try {
      final r = await http
          .get(Uri.parse('http://127.0.0.1:9090/version'))
          .timeout(const Duration(seconds: 1));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Best-effort human explanation from the captured log.
  String _diagnose() {
    final log = _logTail.join('\n').toLowerCase();
    if (log.contains('permission') || log.contains('access is denied')) {
      return 'Нужны права администратора — запустите Aurora от имени администратора.';
    }
    if (log.contains('wintun') || log.contains('create tun') || log.contains('adapter')) {
      return 'Не удалось создать TUN-адаптер. Скорее всего активен другой VPN — закройте NekoBox/Happ/WireGuard и повторите.';
    }
    if (log.contains('bind') || log.contains('address already in use')) {
      return 'Порт занят другим клиентом. Закройте другие VPN и повторите.';
    }
    return 'Ядро не запустилось. Проверьте, что не активен другой VPN, и повторите.';
  }

  /// Adds a live check for a competing TUN adapter to the log-based guess.
  Future<String> _diagnoseAsync() async {
    if (await _hasForeignTun()) {
      return 'Обнаружен другой активный VPN (NekoBox/WireGuard). Закройте его — два туннеля не могут работать одновременно.';
    }
    return _diagnose();
  }

  /// True if a non-Aurora TUN/WireGuard adapter is currently up.
  Future<bool> _hasForeignTun() async {
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "(Get-NetAdapter | Where-Object { \$_.Status -eq 'Up' -and "
            "(\$_.InterfaceDescription -match 'sing-tun|wireguard|wintun') -and "
            "\$_.Name -ne 'aurora-tun' }).Name -join ','",
      ]);
      return (r.stdout as String).trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Terminates only *our* sing-box (matched by path), never another client's.
  Future<void> _killOwnCore() async {
    try {
      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "Get-Process sing-box -ErrorAction SilentlyContinue | "
            "Where-Object { \$_.Path -eq '$_corePath' } | Stop-Process -Force",
      ]);
    } catch (_) {}
  }

  void _startPolling() {
    _lastUp = 0;
    _lastDown = 0;
    _poller = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final r = await http
            .get(Uri.parse('http://127.0.0.1:9090/connections'))
            .timeout(const Duration(seconds: 2));
        if (r.statusCode != 200) return;
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final up = (data['uploadTotal'] as num?)?.toInt() ?? _stats.uploadTotal;
        final down =
            (data['downloadTotal'] as num?)?.toInt() ?? _stats.downloadTotal;
        _stats = _stats.copyWith(
          uploadTotal: up,
          downloadTotal: down,
          uploadSpeed: (up - _lastUp).clamp(0, 1 << 40).toDouble(),
          downloadSpeed: (down - _lastDown).clamp(0, 1 << 40).toDouble(),
        );
        _lastUp = up;
        _lastDown = down;
        _statsCtrl.add(_stats);
      } catch (_) {}
    });
  }

  @override
  Future<void> stop() async {
    _emit(ConnectionStatus.disconnecting);
    _cleanup();
    await _killOwnCore();
    _stats = ConnectionStats.empty;
    _statsCtrl.add(_stats);
    _emit(ConnectionStatus.disconnected);
  }

  void _cleanup() {
    _poller?.cancel();
    _poller = null;
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
  }

  @override
  void dispose() {
    _cleanup();
    _statusCtrl.close();
    _statsCtrl.close();
  }
}
