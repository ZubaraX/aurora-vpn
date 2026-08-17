import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/connection_stats.dart';
import '../data/models/enums.dart';
import '../data/models/proxy_node.dart';
import '../engine/reconnect_policy.dart';
import '../engine/tunnel_health.dart';
import '../engine/vpn_engine.dart';
import '../engine/windows_engine.dart';
import 'profile_controller.dart';
import 'providers.dart';
import 'settings_controller.dart';

class ConnectionUiState {
  const ConnectionUiState({
    this.status = ConnectionStatus.disconnected,
    this.stats = ConnectionStats.empty,
    this.message,
  });

  final ConnectionStatus status;
  final ConnectionStats stats;
  final String? message;

  ConnectionUiState copyWith({
    ConnectionStatus? status,
    ConnectionStats? stats,
    String? message,
    bool clearMessage = false,
  }) => ConnectionUiState(
    status: status ?? this.status,
    stats: stats ?? this.stats,
    message: clearMessage ? null : (message ?? this.message),
  );
}

/// Bridges the [VpnEngine] streams into UI state and exposes the connect /
/// disconnect intent. Resolving *which* node to connect (explicit selection →
/// fastest tested → first available) lives here so every entry point agrees.
class ConnectionController extends StateNotifier<ConnectionUiState> {
  ConnectionController(this._ref, this._engine)
    : super(const ConnectionUiState()) {
    _statusSub = _engine.statusStream.listen((s) {
      state = state.copyWith(status: s);
      if (s == ConnectionStatus.connected) {
        _health.reset();
        _startHealthWatch();
      } else {
        _healthTimer?.cancel();
        _healthTimer = null;
      }
      if ((s == ConnectionStatus.error || s == ConnectionStatus.disconnected) &&
          _wantsConnection &&
          !_transitioning) {
        _scheduleReconnect();
      }
    });
    _statsSub = _engine.statsStream.listen((s) {
      state = state.copyWith(stats: s);
      _maybeAutoRefresh();
    });
  }

  // Stats arrive from the native service every second and keep flowing while
  // the app is backgrounded (the VPN foreground service keeps the process
  // alive) — unlike a Dart Timer, which Android freezes in the background. So
  // we hang the subscription refresh off this native clock: it keeps profiles
  // current in the background where the periodic timer would be suspended.
  DateTime _lastRefreshTick = DateTime.fromMillisecondsSinceEpoch(0);
  void _maybeAutoRefresh() {
    final now = DateTime.now();
    if (now.difference(_lastRefreshTick) < const Duration(minutes: 10)) return;
    _lastRefreshTick = now;
    _ref
        .read(profileProvider.notifier)
        .refreshIfStale(maxAge: const Duration(minutes: 9));
  }

  final Ref _ref;
  final VpnEngine _engine;
  StreamSubscription? _statusSub;
  StreamSubscription? _statsSub;
  int _operation = 0;
  final _reconnectPolicy = ReconnectPolicy();
  Timer? _reconnectTimer;
  Timer? _healthTimer;
  final _health = TunnelHealth();
  bool _healthChecking = false;
  bool _wantsConnection = false;
  bool _transitioning = false;
  String? _desiredNodeId;
  List<String> _desiredCandidateIds = const [];

  bool get isRealCore => _engine.isRealCore;
  String get backendLabel => _engine.backendLabel;

  /// The engine's most recent failure reason, shown on the Home error banner.
  String? get lastError => _engine.lastError;

  /// Windows core logs for the in-app Logs screen (Android reads its own via a
  /// platform channel).
  String get diagnostics {
    final e = _engine;
    return e is WindowsProcessEngine ? e.logTail : '';
  }

  /// Pings all nodes, then connects to the lowest-latency reachable one.
  Future<void> connectFastest() async {
    await _ref.read(profileProvider.notifier).pingAll();
    final fastest = _ref.read(profileProvider.notifier).fastestNode();
    final node = fastest ?? _resolveNode();
    if (node == null) {
      state = state.copyWith(message: 'Добавьте сервер или подписку');
      return;
    }
    await connectTo(node);
  }

  Future<void> toggle() async {
    if (state.status.isActive) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> connect() async {
    final node = _resolveNode();
    if (node == null) {
      state = state.copyWith(message: 'Добавьте сервер или подписку');
      return;
    }
    await _connectRequested(node);
  }

  Future<void> connectTo(ProxyNode node) async {
    await _connectRequested(node);
  }

  /// Runs the engine's traffic probe once, for the diagnostics screen.
  Future<bool> probeTunnel() async {
    if (state.status != ConnectionStatus.connected) return false;
    try {
      return await _engine.verifyConnection();
    } catch (_) {
      return false;
    }
  }

  /// Watches the live tunnel and switches servers when the active one stops
  /// passing traffic.
  ///
  /// Until now the traffic check only ran at connect time, so a server that
  /// died mid-session (gateway 504s, refused dials, timeouts) left the tunnel
  /// "connected" but useless until the user intervened. Two consecutive failed
  /// probes are required so a single blip never causes a needless switch.
  void _startHealthWatch() {
    _healthTimer?.cancel();
    // First check soon after connecting: when the server is unreachable on the
    // current network every DNS query hangs for 10-30s, so the phone is
    // effectively offline. Catching it in ~20s (and switching after the second
    // failure) beats waiting a full minute per probe.
    Timer(const Duration(seconds: 20), () {
      if (state.status == ConnectionStatus.connected) unawaited(_healthCheck());
    });
    _healthTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_healthCheck()),
    );
  }

  Future<void> _healthCheck() async {
    if (_healthChecking ||
        _transitioning ||
        state.status != ConnectionStatus.connected) {
      return;
    }
    _healthChecking = true;
    try {
      // First make sure a tunnel still exists at all. Android can tear the VPN
      // down without telling us, and we were happily reporting "Защищено" over
      // a dead interface while every app went out unprotected.
      if (!await _engine.tunnelAlive()) {
        if (state.status != ConnectionStatus.connected) return;
        state = state.copyWith(
          status: ConnectionStatus.disconnected,
          message: 'Система отключила VPN — переподключаемся',
        );
        _health.reset();
        if (_wantsConnection) _scheduleReconnect();
        return;
      }
      // Thorough probe here: a live tunnel must not be torn down over a tight
      // deadline. Connect-time candidate screening keeps the fast probe.
      final ok = await _engine.verifyConnection(thorough: true);
      if (_transitioning || state.status != ConnectionStatus.connected) return;
      final stats = state.stats;
      final switchServer = _health.sample(
        probeOk: ok,
        totalBytes: stats.uploadTotal + stats.downloadTotal,
      );
      if (!switchServer) return;
      _health.reset();

      // Prefer the user's failover pool (rotated past the failing node);
      // otherwise fall back to other servers, keeping the current one last.
      final current = _ref.read(profileProvider).nodeById(_desiredNodeId);
      final pool = _rotatedDesiredCandidates();
      final List<ProxyNode> candidates;
      if (pool.isNotEmpty) {
        candidates = pool;
      } else if (current != null) {
        candidates = [
          ..._fallbackCandidates(current).where((n) => n.id != current.id).take(3),
          current,
        ];
      } else {
        return;
      }
      if (candidates.length < 2) return;
      state = state.copyWith(
        message: 'Сервер перестал передавать трафик — переключаемся',
      );
      await _connectVerified(candidates.first, candidatesOverride: candidates);
    } catch (_) {
      // Never let a health check break the live tunnel.
    } finally {
      _healthChecking = false;
    }
  }

  /// Regenerates the tunnel config with the current settings (e.g. after domain
  /// zones / routing changed) by reloading the active node. No-op when not
  /// connected. On Android this is an in-place libbox reload, so it applies
  /// almost seamlessly.
  Future<void> reapply() async {
    if (!state.status.isActive) return;
    final node =
        _ref.read(profileProvider).nodeById(_desiredNodeId) ?? _resolveNode();
    if (node == null) return;
    _wantsConnection = true;
    _desiredNodeId = node.id;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectPolicy.reset();
    await _connectVerified(node);
  }

  /// Connects to a specific node by id; empty/unknown id falls back to the
  /// normal resolution (used by trigger apps that target a chosen profile).
  Future<void> connectToId(String? nodeId) async {
    if (nodeId == null || nodeId.isEmpty) return connect();
    final node = _ref.read(profileProvider).nodeById(nodeId);
    if (node != null) return connectTo(node);
    return connect();
  }

  /// Connects through an ordered, user-selected failover pool.
  ///
  /// Each candidate is verified with a real proxied HTTPS request. Missing
  /// node ids (for example after a subscription refresh) are skipped.
  Future<void> connectToIds(Iterable<String> nodeIds) async {
    final profile = _ref.read(profileProvider);
    final seen = <String>{};
    final nodes = <ProxyNode>[];
    for (final id in nodeIds) {
      if (id.isEmpty || !seen.add(id)) continue;
      final node = profile.nodeById(id);
      if (node != null) nodes.add(node);
      if (nodes.length == 20) break;
    }
    if (nodes.isEmpty) return connect();

    final ids = nodes.map((node) => node.id).toList(growable: false);
    if (_sameCandidates(ids, _desiredCandidateIds) &&
        state.status.isActive &&
        ids.contains(_ref.read(settingsProvider).activeNodeId)) {
      return;
    }

    _wantsConnection = true;
    _desiredNodeId = nodes.first.id;
    _desiredCandidateIds = ids;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectPolicy.reset();
    await _connectVerified(nodes.first, candidatesOverride: nodes);
  }

  Future<void> disconnect() {
    _wantsConnection = false;
    _desiredNodeId = null;
    _desiredCandidateIds = const [];
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectPolicy.reset();
    _operation++;
    _transitioning = false;
    return _engine.stop();
  }

  Future<void> _connectRequested(ProxyNode node) async {
    if (_desiredNodeId == node.id &&
        (state.status == ConnectionStatus.connecting ||
            state.status == ConnectionStatus.connected)) {
      return;
    }
    _wantsConnection = true;
    _desiredNodeId = node.id;
    _desiredCandidateIds = const [];
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectPolicy.reset();
    await _connectVerified(node);
  }

  Future<void> _connectVerified(
    ProxyNode preferred, {
    List<ProxyNode>? candidatesOverride,
  }) async {
    final operation = ++_operation;
    _transitioning = true;
    state = state.copyWith(clearMessage: true);
    final raw =
        candidatesOverride ?? _fallbackCandidates(preferred).take(4).toList();
    // Try servers that aren't known-dead first — demote ones whose last ping
    // timed out (latencyMs < 0) to the end, preserving the user's order within
    // each group. This reaches a working server quickly instead of burning the
    // per-candidate connect+probe budget on servers that just timed out.
    final candidates = [
      for (final n in raw)
        if ((n.latencyMs ?? 0) >= 0) n,
      for (final n in raw)
        if ((n.latencyMs ?? 0) < 0) n,
    ];

    try {
      // The first candidate that reaches "connected" (core up, TUN attached)
      // even if its traffic probe did not answer. On Android "connected" means
      // the core loaded — the VLESS/Reality outbound dials lazily on the first
      // request — so a probe miss is often a slow cold handshake or a blocked
      // test endpoint, not a dead exit. Rather than tearing everything down with
      // "no traffic" (while the very same server works in other clients), we keep
      // this connection as a soft fallback, mirroring how mainstream clients
      // simply stay connected.
      ProxyNode? connectedFallback;

      for (final node in candidates) {
        if (operation != _operation) return;
        _desiredNodeId = node.id;
        _ref.read(settingsProvider.notifier).setActiveNode(node.id);
        try {
          await _engine.replace(
            node,
            _ref.read(settingsProvider),
            nodes: _ref.read(profileProvider).nodes,
          );
        } catch (_) {
          if (operation != _operation) return;
          continue;
        }
        final started = await _waitForConnected();
        if (operation != _operation) return;
        if (!started) {
          // A native start can occasionally stall without producing an error
          // event (for example during a radio handover). Tear that half-start
          // down so the bounded reconnect policy can make a clean attempt.
          if (_engine.status == ConnectionStatus.connecting) {
            await _engine.stop();
          }
          continue;
        }
        connectedFallback ??= node;

        final reachable = await _engine.verifyConnection();
        if (operation != _operation) return;
        if (reachable) {
          _desiredNodeId = node.id;
          _reconnectPolicy.reset();
          _reconnectTimer?.cancel();
          _reconnectTimer = null;
          if (node.id != preferred.id) {
            state = state.copyWith(
              message: candidatesOverride == null
                  ? 'Выбранный сервер не передавал трафик — подключён резервный'
                  : 'Подключён первый рабочий сервер из мобильного списка',
            );
          }
          return;
        }

        // Keep the command server alive between candidates. Android reloads the
        // existing libbox service in place; desktop engines perform their own
        // orderly stop inside replace().
      }

      if (operation != _operation) return;

      // None of the candidates passed the traffic probe. If at least one is
      // actually connected, stay on it instead of dropping to "no traffic" —
      // the probe endpoint may just be unreachable from that exit.
      if (connectedFallback != null) {
        if (_desiredNodeId != connectedFallback.id) {
          _desiredNodeId = connectedFallback.id;
          _ref.read(settingsProvider.notifier).setActiveNode(connectedFallback.id);
          try {
            await _engine.replace(
              connectedFallback,
              _ref.read(settingsProvider),
              nodes: _ref.read(profileProvider).nodes,
            );
            await _waitForConnected();
          } catch (_) {}
          if (operation != _operation) return;
        }
        _reconnectPolicy.reset();
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        state = state.copyWith(
          message: 'Подключено. Проверка трафика не прошла — '
              'если сайты не открываются, смените сервер.',
        );
        return;
      }

      await _engine.stop();
      state = state.copyWith(
        message: 'Не удалось подключиться ни к одному серверу из списка',
      );
    } finally {
      if (operation == _operation) {
        _transitioning = false;
        if (_wantsConnection &&
            (state.status == ConnectionStatus.error ||
                state.status == ConnectionStatus.disconnected)) {
          _scheduleReconnect();
        }
      }
    }
  }

  void _scheduleReconnect() {
    if (!_wantsConnection ||
        _transitioning ||
        _reconnectTimer?.isActive == true) {
      return;
    }
    final delay = _reconnectPolicy.nextDelay();
    if (delay == null) {
      _wantsConnection = false;
      state = state.copyWith(
        message: 'Автопереподключение не удалось — попробуйте другой сервер',
      );
      return;
    }
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_wantsConnection || state.status.isActive) return;
      final failover = _rotatedDesiredCandidates();
      if (failover.isNotEmpty) {
        unawaited(
          _connectVerified(failover.first, candidatesOverride: failover),
        );
        return;
      }
      final desired = _desiredNodeId;
      final node = desired == null
          ? _resolveNode()
          : _ref.read(profileProvider).nodeById(desired) ?? _resolveNode();
      if (node == null) {
        _wantsConnection = false;
        return;
      }
      unawaited(_connectVerified(node));
    });
  }

  List<ProxyNode> _rotatedDesiredCandidates() {
    if (_desiredCandidateIds.isEmpty) return const [];
    final profile = _ref.read(profileProvider);
    final ids = [..._desiredCandidateIds];
    final failedIndex = ids.indexOf(_desiredNodeId ?? '');
    if (failedIndex >= 0 && ids.length > 1) {
      final after = ids.sublist(failedIndex + 1);
      final throughFailed = ids.sublist(0, failedIndex + 1);
      ids
        ..clear()
        ..addAll(after)
        ..addAll(throughFailed);
    }
    return ids
        .map(profile.nodeById)
        .whereType<ProxyNode>()
        .toList(growable: false);
  }

  static bool _sameCandidates(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<bool> _waitForConnected() async {
    if (_engine.status == ConnectionStatus.connected) return true;
    try {
      final result = await _engine.statusStream
          .firstWhere(
            (status) =>
                status == ConnectionStatus.connected ||
                status == ConnectionStatus.error,
          )
          .timeout(const Duration(seconds: 10));
      return result == ConnectionStatus.connected;
    } on TimeoutException {
      state = state.copyWith(message: 'Истекло время ожидания VPN');
      return false;
    }
  }

  Iterable<ProxyNode> _fallbackCandidates(ProxyNode preferred) {
    final nodes = _ref.read(profileProvider).nodes;
    final security = '${preferred.params['security']}';
    final transport = '${preferred.params['network']}';
    final preferDifferentTransport = security == 'reality';
    final alternatives = nodes.where((node) => node.id != preferred.id).toList()
      ..sort((a, b) {
        final aDifferent =
            '${a.params['security']}' != security ||
            '${a.params['network']}' != transport;
        final bDifferent =
            '${b.params['security']}' != security ||
            '${b.params['network']}' != transport;
        if (aDifferent != bDifferent) {
          return aDifferent == preferDifferentTransport ? -1 : 1;
        }
        final aLatency = (a.latencyMs == null || a.latencyMs! < 0)
            ? 1 << 30
            : a.latencyMs!;
        final bLatency = (b.latencyMs == null || b.latencyMs! < 0)
            ? 1 << 30
            : b.latencyMs!;
        return aLatency.compareTo(bLatency);
      });
    return [preferred, ...alternatives];
  }

  ProxyNode? _resolveNode() {
    final settings = _ref.read(settingsProvider);
    final profile = _ref.read(profileProvider);
    final selected = profile.nodeById(settings.activeNodeId);
    if (selected != null) return selected;
    final fastest = _ref.read(profileProvider.notifier).fastestNode();
    if (fastest != null) return fastest;
    return profile.nodes.isEmpty ? null : profile.nodes.first;
  }

  void clearMessage() => state = state.copyWith(clearMessage: true);

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _healthTimer?.cancel();
    _statusSub?.cancel();
    _statsSub?.cancel();
    super.dispose();
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionController, ConnectionUiState>((ref) {
      return ConnectionController(ref, ref.watch(engineProvider));
    });

/// The currently selected node (or null), derived from settings + profile.
final activeNodeProvider = Provider<ProxyNode?>((ref) {
  final settings = ref.watch(settingsProvider);
  final profile = ref.watch(profileProvider);
  return profile.nodeById(settings.activeNodeId);
});

/// Installed apps for the per-app routing screen.
final installedAppsProvider = FutureProvider((ref) async {
  return ref.watch(appInventoryProvider).list();
});
