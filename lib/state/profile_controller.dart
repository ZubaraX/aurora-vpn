import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/local/storage.dart';
import '../data/models/proxy_node.dart';
import '../data/models/subscription.dart';
import '../data/parsers/subscription_parser.dart';
import '../engine/latency_service.dart';
import 'providers.dart';

/// Immutable snapshot of all subscriptions and their nodes.
class ProfileState {
  const ProfileState({
    this.subscriptions = const [],
    this.nodes = const [],
    this.busy = false,
    this.error,
  });

  final List<Subscription> subscriptions;
  final List<ProxyNode> nodes;
  final bool busy;
  final String? error;

  /// Manually-imported nodes not tied to a subscription.
  List<ProxyNode> get looseNodes =>
      nodes.where((n) => n.subscriptionId == null).toList();

  List<ProxyNode> nodesOf(String subId) =>
      nodes.where((n) => n.subscriptionId == subId).toList();

  ProxyNode? nodeById(String? id) {
    if (id == null) return null;
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  ProfileState copyWith({
    List<Subscription>? subscriptions,
    List<ProxyNode>? nodes,
    bool? busy,
    String? error,
    bool clearError = false,
  }) => ProfileState(
    subscriptions: subscriptions ?? this.subscriptions,
    nodes: nodes ?? this.nodes,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Manages subscriptions and nodes: import, refresh, remove, ping.
class ProfileController extends StateNotifier<ProfileState> {
  ProfileController(this._storage, this._parser, this._latency)
    : super(const ProfileState()) {
    _restore();
    _startAutoPing();
    _startAutoRefresh();
  }

  final Storage _storage;
  final SubscriptionParser _parser;
  final LatencyService _latency;
  final _rng = Random();
  Timer? _autoPing;
  Timer? _autoRefresh;
  bool _refreshingSubscriptions = false;
  final _fetchingSubscriptionIds = <String>{};

  /// Keeps latency fresh in real time: an initial sweep shortly after launch,
  /// then a full re-ping every 7 minutes.
  void _startAutoPing() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && state.nodes.isNotEmpty) pingAll();
    });
    _autoPing = Timer.periodic(const Duration(minutes: 7), (_) {
      if (state.nodes.isNotEmpty) pingAll();
    });
  }

  /// Refresh shortly after launch and every five minutes while the app lives.
  /// A freshness guard prevents duplicate downloads on rapid resume events.
  void _startAutoRefresh() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) refreshIfStale(maxAge: const Duration(minutes: 2));
    });
    _autoRefresh = Timer.periodic(const Duration(minutes: 5), (_) {
      refreshIfStale(maxAge: const Duration(minutes: 4));
    });
  }

  @override
  void dispose() {
    _autoPing?.cancel();
    _autoRefresh?.cancel();
    super.dispose();
  }

  void _restore() {
    final subs = _storage
        .readList(Storage.kSubscriptions)
        .map(Subscription.fromJson)
        .toList();
    final nodes = _storage
        .readList(Storage.kNodes)
        .map(ProxyNode.fromJson)
        .toList();
    state = state.copyWith(subscriptions: subs, nodes: nodes);
  }

  void _persist() {
    _storage.writeJson(
      Storage.kSubscriptions,
      state.subscriptions.map((s) => s.toJson()).toList(),
    );
    _storage.writeJson(
      Storage.kNodes,
      state.nodes.map((n) => n.toJson()).toList(),
    );
  }

  String _genId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rng.nextInt(1 << 20).toRadixString(36)}';

  // --- Import --------------------------------------------------------------

  /// Decides whether pasted text is a subscription URL or inline node links.
  Future<void> import(String text, {String? name}) async {
    final trimmed = text.trim();
    final isHttpSub =
        (trimmed.startsWith('http://') || trimmed.startsWith('https://')) &&
        !trimmed.contains('\n');
    if (isHttpSub) {
      await addSubscription(name ?? '', trimmed);
    } else {
      _addLooseNodes(trimmed);
    }
  }

  Future<void> addSubscription(String name, String url) async {
    final id = _genId();
    final sub = Subscription(
      id: id,
      name: name.trim().isEmpty ? _hostOf(url) : name.trim(),
      url: url,
      addedAt: DateTime.now(),
    );
    state = state.copyWith(
      subscriptions: [...state.subscriptions, sub],
      busy: true,
      clearError: true,
    );
    await _fetch(sub);
  }

  Future<void> refreshSubscription(String subId) async {
    final sub = state.subscriptions.firstWhere((s) => s.id == subId);
    state = state.copyWith(busy: true, clearError: true);
    await _fetch(sub);
  }

  Future<void> refreshAll() async {
    await _refreshSubscriptions(
      state.subscriptions.where((sub) => sub.autoUpdate),
    );
  }

  Future<void> refreshIfStale({
    Duration maxAge = const Duration(minutes: 2),
  }) async {
    await _refreshSubscriptions(
      state.subscriptions.where(
        (sub) => sub.autoUpdate && sub.isStale(maxAge: maxAge),
      ),
    );
  }

  Future<void> _refreshSubscriptions(
    Iterable<Subscription> subscriptions,
  ) async {
    if (_refreshingSubscriptions) return;
    final pending = subscriptions.toList();
    if (pending.isEmpty) return;
    _refreshingSubscriptions = true;
    try {
      for (final sub in pending) {
        if (!mounted) return;
        await _fetch(sub);
      }
    } finally {
      _refreshingSubscriptions = false;
    }
  }

  Future<void> _fetch(Subscription sub) async {
    if (!_fetchingSubscriptionIds.add(sub.id)) {
      state = state.copyWith(busy: false);
      return;
    }
    try {
      final resp = await http
          .get(
            Uri.parse(sub.url),
            headers: {
              'User-Agent': 'Aurora/1.1 (sing-box)',
              'Cache-Control': 'no-cache, no-store',
              'Pragma': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) {
        _finishWithError('Сервер вернул ${resp.statusCode}');
        return;
      }

      final parsed = _parser.parseContent(resp.body, subscriptionId: sub.id);
      final info = _parseUserInfo(resp.headers['subscription-userinfo']);

      final updated = sub.copyWith(
        lastUpdated: DateTime.now(),
        nodeCount: parsed.length,
        uploadBytes: info?.$1,
        downloadBytes: info?.$2,
        totalBytes: info?.$3,
        expireUnix: info?.$4,
      );

      final otherNodes = state.nodes
          .where((n) => n.subscriptionId != sub.id)
          .toList();
      final subs = [
        for (final s in state.subscriptions) s.id == sub.id ? updated : s,
      ];
      state = state.copyWith(
        subscriptions: subs,
        nodes: [...otherNodes, ...parsed],
        busy: false,
      );
      _persist();
    } catch (e) {
      _finishWithError('Не удалось загрузить подписку');
    } finally {
      _fetchingSubscriptionIds.remove(sub.id);
    }
  }

  void _finishWithError(String message) {
    state = state.copyWith(busy: false, error: message);
    _persist();
  }

  void _addLooseNodes(String content) {
    final parsed = _parser.parseContent(content);
    if (parsed.isEmpty) {
      state = state.copyWith(error: 'Не найдено ни одного узла');
      return;
    }
    state = state.copyWith(
      nodes: [...state.nodes, ...parsed],
      clearError: true,
    );
    _persist();
  }

  // --- Remove --------------------------------------------------------------

  void removeSubscription(String subId) {
    state = state.copyWith(
      subscriptions: state.subscriptions.where((s) => s.id != subId).toList(),
      nodes: state.nodes.where((n) => n.subscriptionId != subId).toList(),
    );
    _persist();
  }

  void removeNode(String nodeId) {
    state = state.copyWith(
      nodes: state.nodes.where((n) => n.id != nodeId).toList(),
    );
    _persist();
  }

  void toggleAutoUpdate(String subId) {
    final subs = [
      for (final s in state.subscriptions)
        s.id == subId ? s.copyWith(autoUpdate: !s.autoUpdate) : s,
    ];
    state = state.copyWith(subscriptions: subs);
    _persist();
  }

  void clearError() => state = state.copyWith(clearError: true);

  // --- Latency -------------------------------------------------------------

  /// Pings all nodes concurrently (bounded) and records latency.
  Future<void> pingAll() async {
    final nodes = state.nodes;
    final results = <String, int>{};
    const batch = 12;
    for (var i = 0; i < nodes.length; i += batch) {
      final slice = nodes.skip(i).take(batch);
      await Future.wait(
        slice.map((n) async {
          results[n.id] = await _latency.ping(n.server, n.port);
        }),
      );
      _applyLatency(results);
    }
  }

  Future<void> pingNode(String nodeId) async {
    final node = state.nodeById(nodeId);
    if (node == null) return;
    final ms = await _latency.ping(node.server, node.port);
    _applyLatency({nodeId: ms});
  }

  void _applyLatency(Map<String, int> results) {
    final nodes = [
      for (final n in state.nodes)
        results.containsKey(n.id) ? n.copyWith(latencyMs: results[n.id]) : n,
    ];
    state = state.copyWith(nodes: nodes);
  }

  /// The reachable node with the lowest latency, if any were tested.
  ProxyNode? fastestNode() {
    final tested = state.nodes.where((n) => (n.latencyMs ?? -1) >= 0).toList()
      ..sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
    return tested.isEmpty ? null : tested.first;
  }

  // --- helpers -------------------------------------------------------------

  String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return 'Подписка';
    }
  }

  /// Parses `upload=..; download=..; total=..; expire=..` → tuple.
  (int, int, int, int)? _parseUserInfo(String? header) {
    if (header == null) return null;
    int read(String key) {
      final m = RegExp('$key=(\\d+)').firstMatch(header);
      return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
    }

    return (read('upload'), read('download'), read('total'), read('expire'));
  }
}

final profileProvider = StateNotifierProvider<ProfileController, ProfileState>((
  ref,
) {
  return ProfileController(
    ref.watch(storageProvider),
    ref.watch(subscriptionParserProvider),
    ref.watch(latencyServiceProvider),
  );
});
