import 'storage.dart';
import '../models/proxy_node.dart';

/// One-time migration to the content-based [ProxyNode.identityId].
///
/// Earlier builds derived node ids from the subscription list position, so a
/// provider reordering its servers (or two profiles sharing a server) broke or
/// merged saved selections. The new id is a hash of the node's full identity.
///
/// This remaps persisted ids using the stored nodes' OWN `id → identityId`
/// linkage (the same snapshot the selections were saved against), so trigger
/// profiles / domain-zone rules / the active selection carry over without the
/// user re-selecting. It is a pure transform over the stored JSON and a no-op
/// once ids already match.
class NodeIdMigration {
  const NodeIdMigration._();

  /// Migrates in place on [storage]. Safe to call on every launch.
  static void run(Storage storage) {
    final nodesRaw = storage.readList(Storage.kNodes);
    if (nodesRaw.isEmpty) return;

    final idMap = <String, String>{};
    final migratedNodes = <Map<String, dynamic>>[];
    var changed = false;
    for (final j in nodesRaw) {
      try {
        final node = ProxyNode.fromJson(Map<String, dynamic>.from(j as Map));
        final newId = node.identityId;
        if (newId != node.id) changed = true;
        idMap[node.id] = newId;
        migratedNodes.add(node.copyWith(id: newId).toJson());
      } catch (_) {
        // Keep unparseable records untouched.
        migratedNodes.add(Map<String, dynamic>.from(j as Map));
      }
    }
    if (!changed) return;

    storage.writeJson(Storage.kNodes, migratedNodes);

    final settings = storage.readMap(Storage.kSettings);
    if (settings == null) return;
    storage.writeJson(Storage.kSettings, remapSettings(settings, idMap));
  }

  /// Rewrites every node-id-bearing field of a settings map through [idMap].
  /// Values that aren't known node ids (empty, `direct`/`proxy`/`block`) pass
  /// through unchanged. Exposed for testing.
  static Map<String, dynamic> remapSettings(
    Map<String, dynamic> settings,
    Map<String, String> idMap,
  ) {
    String mapId(String id) => idMap[id] ?? id;
    final out = Map<String, dynamic>.from(settings);

    final active = out['activeNodeId'];
    if (active is String) out['activeNodeId'] = mapId(active);

    for (final key in const ['triggerApps', 'triggerWifiProfiles', 'domainZoneRules']) {
      final m = out[key];
      if (m is Map) {
        out[key] = m.map(
          (k, v) => MapEntry('$k', v is String ? mapId(v) : v),
        );
      }
    }

    final mobile = out['triggerMobileProfiles'];
    if (mobile is Map) {
      out['triggerMobileProfiles'] = mobile.map(
        (k, v) => MapEntry(
          '$k',
          v is List ? [for (final e in v) e is String ? mapId(e) : e] : v,
        ),
      );
    }
    return out;
  }
}
