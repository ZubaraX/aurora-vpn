import 'dart:convert';
import 'dart:io';

/// File-backed JSON persistence (one file per key) — a drop-in for the previous
/// SharedPreferences store, with no native plugin. Controllers own the shape of
/// what they store; this just reads and writes typed blobs synchronously.
class Storage {
  Storage(this._dir);
  final Directory _dir;

  static const kSubscriptions = 'aurora.subscriptions';
  static const kNodes = 'aurora.nodes';
  static const kSettings = 'aurora.settings';

  File _file(String key) =>
      File('${_dir.path}${Platform.pathSeparator}$key.json');

  String? _read(String key) {
    final f = _file(key);
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  List<Map<String, dynamic>> readList(String key) {
    final raw = _read(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
      }
    } catch (_) {}
    return [];
  }

  Map<String, dynamic>? readMap(String key) {
    final raw = _read(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> writeJson(String key, Object value) async {
    // Synchronous flush so a selection can't be lost if the app is closed
    // immediately after a toggle.
    _file(key).writeAsStringSync(jsonEncode(value));
  }
}
