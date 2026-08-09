import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../data/local/app_paths.dart';
import '../constants.dart';

/// Describes an available release newer than the running build.
class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.windowsUrl,
    this.androidUrl,
  });

  final String version;
  final String notes;
  final String pageUrl;
  final String? windowsUrl;
  final String? androidUrl;

  /// The asset relevant to the current platform, if any.
  String? get assetForPlatform =>
      Platform.isWindows ? windowsUrl : (Platform.isAndroid ? androidUrl : null);
}

/// Checks GitHub Releases for a newer build and applies the update in place.
///
/// Windows: downloads the release zip and hands off to a tiny updater script
/// that waits for Aurora to exit, swaps the files and relaunches. Android: opens
/// the APK so the system installer can take over.
class UpdateService {
  const UpdateService();

  static const _channel = MethodChannel('aurora/update');

  Future<UpdateInfo?> check() async {
    try {
      final r = await http.get(
        Uri.parse(kReleasesApi),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final tag = '${j['tag_name'] ?? ''}'.replaceFirst('v', '');
      if (tag.isEmpty || !_isNewer(tag, kAppVersion)) return null;

      String? win, apk;
      for (final a in (j['assets'] as List? ?? const [])) {
        final name = '${a['name']}'.toLowerCase();
        final url = '${a['browser_download_url']}';
        if (name.endsWith('.zip') || name.contains('windows')) win = url;
        if (name.endsWith('.apk')) apk = url;
      }
      return UpdateInfo(
        version: tag,
        notes: '${j['body'] ?? ''}',
        pageUrl: '${j['html_url'] ?? kReleasesPage}',
        windowsUrl: win,
        androidUrl: apk,
      );
    } catch (_) {
      return null;
    }
  }

  /// Posts a system notification (Android) announcing [version]. No-op on other
  /// platforms; failures are swallowed.
  Future<void> notifyAvailable(String version) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('notifyUpdate', {'version': version});
    } catch (_) {}
  }

  /// Downloads and applies [info] for the current platform. Returns false if
  /// there is nothing to do (no asset).
  Future<bool> apply(UpdateInfo info, {void Function(double)? onProgress}) async {
    final url = info.assetForPlatform;
    if (url == null) return false;
    if (Platform.isWindows) return _applyWindows(url, onProgress);
    if (Platform.isAndroid) return _applyAndroid(url, onProgress);
    return false;
  }

  // --- Windows: download zip, swap via updater script, relaunch -------------

  Future<bool> _applyWindows(String url, void Function(double)? onProgress) async {
    final dir = Directory.systemTemp;
    final zip = File('${dir.path}\\aurora-update.zip');
    await _download(url, zip, onProgress);

    final installDir = File(Platform.resolvedExecutable).parent.path;
    final exe = Platform.resolvedExecutable;
    final extract = '${dir.path}\\aurora-update';
    final bat = File('${dir.path}\\aurora-update.bat');

    // Wait for this process to exit, replace files, relaunch.
    await bat.writeAsString('''
@echo off
timeout /t 2 /nobreak >nul
powershell -NoProfile -Command "Expand-Archive -Path '${zip.path}' -DestinationPath '$extract' -Force"
robocopy "$extract" "$installDir" /E /IS /NFL /NDL /NJH /NJS >nul
start "" "$exe"
''');

    await Process.start(
      'cmd.exe',
      ['/c', bat.path],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
    exit(0); // let the updater take over
  }

  // --- Android: download APK, hand to the system installer -----------------

  Future<bool> _applyAndroid(String url, void Function(double)? onProgress) async {
    final dir = AppPaths.dataDir();
    final apk = File('${dir.path}/aurora-update.apk');
    await _download(url, apk, onProgress);
    try {
      await _channel.invokeMethod('installApk', {'path': apk.path});
      return true;
    } catch (_) {
      // Fall back to opening the release page in the browser.
      try {
        await _channel.invokeMethod('openUrl', {'url': kReleasesPage});
      } catch (_) {}
      return false;
    }
  }

  Future<void> _download(String url, File dest, void Function(double)? onProgress) async {
    final req = http.Request('GET', Uri.parse(url));
    final resp = await http.Client().send(req);
    final total = resp.contentLength ?? 0;
    var received = 0;
    final sink = dest.openWrite();
    await resp.stream.forEach((chunk) {
      received += chunk.length;
      sink.add(chunk);
      if (total > 0) onProgress?.call(received / total);
    });
    await sink.close();
  }

  /// Semantic-ish comparison: true if [candidate] > [current].
  bool _isNewer(String candidate, String current) {
    List<int> parts(String v) => v
        .split(RegExp(r'[.+\-]'))
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final a = parts(candidate), b = parts(current);
    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
