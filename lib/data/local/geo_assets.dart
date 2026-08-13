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

  static const _names = [
    'geosite-cn.srs',
    'geoip-cn.srs',
    'geosite-ads.srs',
  ];

  /// Directory holding the unpacked rule-sets.
  static Directory dir() =>
      Directory('${AppPaths.dataDir().path}${Platform.pathSeparator}geo');

  /// Absolute path of a rule-set file, for the generated config.
  static String pathOf(String name) =>
      '${dir().path}${Platform.pathSeparator}$name';

  /// True once every rule-set is present on disk.
  static bool get ready =>
      _names.every((n) => File(pathOf(n)).existsSync());

  /// Copies any missing rule-set out of the bundle. Cheap after the first run
  /// (existing files are left alone) and safe to call on every launch; failures
  /// are swallowed so a packaging problem can never block startup — the config
  /// builder falls back to remote rule-sets when [ready] is false.
  static Future<void> unpack() async {
    try {
      final target = dir();
      if (!target.existsSync()) target.createSync(recursive: true);
      for (final name in _names) {
        final file = File(pathOf(name));
        if (file.existsSync() && file.lengthSync() > 0) continue;
        final data = await rootBundle.load('assets/geo/$name');
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
    } catch (_) {}
  }
}
