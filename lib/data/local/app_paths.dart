import 'dart:io';

/// Resolves a writable per-user data directory without the path_provider
/// plugin, so no native code is linked. sing-box configs and persisted state
/// both live here.
class AppPaths {
  AppPaths._();

  static Directory? _cached;

  static Directory dataDir() {
    if (_cached != null) return _cached!;
    final String base;
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      base = '$appData\\Aurora';
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      base = '$home/Library/Application Support/Aurora';
    } else if (Platform.isAndroid) {
      // App-private internal storage; always writable by the app.
      base = '/data/user/0/com.auroravpn.aurora/files/aurora';
    } else {
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      base = '$home/.aurora';
    }
    final dir = Directory(base);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cached = dir;
    return dir;
  }
}
