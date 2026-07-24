import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/connection_stats.dart';
import '../data/models/enums.dart';
import '../data/models/proxy_node.dart';
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
  }) =>
      ConnectionUiState(
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
    });
    _statsSub = _engine.statsStream.listen((s) {
      state = state.copyWith(stats: s);
    });
  }

  final Ref _ref;
  final VpnEngine _engine;
  StreamSubscription? _statusSub;
  StreamSubscription? _statsSub;

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
    _ref.read(settingsProvider.notifier).setActiveNode(node.id);
    await _engine.start(node, _ref.read(settingsProvider));
  }

  Future<void> connectTo(ProxyNode node) async {
    _ref.read(settingsProvider.notifier).setActiveNode(node.id);
    if (state.status.isActive) await _engine.stop();
    await _engine.start(node, _ref.read(settingsProvider));
  }

  /// Connects to a specific node by id; empty/unknown id falls back to the
  /// normal resolution (used by trigger apps that target a chosen profile).
  Future<void> connectToId(String? nodeId) async {
    if (nodeId == null || nodeId.isEmpty) return connect();
    final node = _ref.read(profileProvider).nodeById(nodeId);
    if (node != null) return connectTo(node);
    return connect();
  }

  Future<void> disconnect() => _engine.stop();

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
