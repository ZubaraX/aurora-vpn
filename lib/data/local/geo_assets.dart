import 'dart:io';

import 'package:flutter/services.dart';

import 'app_paths.dart';

/// Unpacks the bundled sing-box rule-sets (`assets/geo/*.srs`) next to the
/// app's data so the core can load them from disk.
///
/// Smart routing used to reference REMOTE rule-sets fetched from GitHub at
/// connect time. On a restricted / white-list network that download is blocked,
/// so the very rules meant to shape traffic could not be obtained. Shipping the
/// files (the approach Happ takes with geoip.dat/geosite.dat) removes the
/// runtime dependency entirely.
class GeoAssets {
  const GeoAssets._();

  static const _names = ['geosite-cn.srs', 'geoip-cn.srs', 'geosite-ads.srs'];

  /// Directory holding the unpacked rule-sets.
  static Directory dir() =>
      Directory('${AppPaths.dataDir().path}${Platform.pathSeparator}geo');

  /// Absolute path of a rule-set file, for the generated config.
  static String pathOf(String name) =>
      '${dir().path}${Platform.pathSeparator}$name';

  /// Test-only override: pins [ready] to a fixed value so config-builder tests
  /// are deterministic regardless of what happens to be unpacked in the host's
  /// app-data directory (a machine where Aurora has run has the files present).
  static bool? debugReadyOverride;

  /// True once every rule-set is present on disk.
  /// Guarded so it can also be evaluated outside a Flutter app (the CI config
  /// validator builds configs in a plain Dart VM): any failure just means the
  /// bundled sets are unavailable and the remote fallback is used.
  static bool get ready {
    if (debugReadyOverride != null) return debugReadyOverride!;
    try {
      return _names.every((n) => File(pathOf(n)).existsSync());
    } catch (_) {
      return false;
    }
  }

  /// Bump whenever a file in `assets/geo/` changes, so existing installs replace
  /// their unpacked copy. Without this the ad/geo lists were frozen at whatever
  /// shipped the day the app was first run: unpack() skipped any file that
  /// already existed, so an updated blocklist never reached anyone who had run
  /// an earlier build.
  static const version = 3;

  static File _stamp() =>
      File('${dir().path}${Platform.pathSeparator}.version');

  /// Copies the rule-sets out of the bundle, replacing stale ones. Cheap after
  /// the first run (a version stamp short-circuits it) and safe to call on every
  /// launch; failures are swallowed so a packaging problem can never block
  /// startup — the config builder falls back to remote rule-sets when [ready]
  /// is false.
  static Future<void> unpack() async {
    try {
      final target = dir();
      if (!target.existsSync()) target.createSync(recursive: true);
      final stamp = _stamp();
      final current = stamp.existsSync()
          ? int.tryParse(stamp.readAsStringSync().trim())
          : null;
      final stale = current != version;
      for (final name in _names) {
        final file = File(pathOf(name));
        if (!stale && file.existsSync() && file.lengthSync() > 0) continue;
        final data = await rootBundle.load('assets/geo/$name');
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      if (stale) await stamp.writeAsString('$version', flush: true);
    } catch (_) {}
  }
}
