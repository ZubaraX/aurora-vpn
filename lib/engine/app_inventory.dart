import 'dart:io';

import 'package:flutter/services.dart';

import '../data/models/installed_app.dart';

/// Supplies the list of apps the user can route per-app.
///
/// - Android: queries the native side (installed launchable apps).
/// - Windows: enumerates real running processes via `tasklist`, so selections
///   map directly onto sing-box `process_name` routing rules.
/// - Anywhere else / on failure: a curated sample so the UI stays explorable.
class AppInventory {
  const AppInventory();

  static const _channel = MethodChannel('aurora/apps');

  Future<List<InstalledApp>> list() async {
    try {
      if (Platform.isAndroid) return await _android();
      if (Platform.isWindows) return await _windows();
    } catch (_) {}
    return _sample();
  }

  /// Ids of currently running apps (Windows: lowercase exe names via tasklist;
  /// Android: foreground/running packages via the native channel). Used by the
  /// trigger-app watcher to auto-connect on launch.
  Future<Set<String>> runningIds() async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run('tasklist', ['/fo', 'csv', '/nh']);
        if (r.exitCode != 0) return {};
        final set = <String>{};
        for (final line in (r.stdout as String).split('\n')) {
          final image = line.split('","').first.replaceAll('"', '').trim();
          if (image.toLowerCase().endsWith('.exe')) {
            set.add(image.toLowerCase());
          }
        }
        return set;
      }
      if (Platform.isAndroid) {
        final ids = await _channel.invokeListMethod<String>('running');
        return ids?.toSet() ?? {};
      }
    } catch (_) {}
    return {};
  }

  /// Active upstream connection used to choose a trigger profile.
  Future<String> activeNetworkType() async {
    if (!Platform.isAndroid) return 'other';
    try {
      return await _channel.invokeMethod<String>('networkType') ?? 'other';
    } catch (_) {
      return 'other';
    }
  }

  Future<bool> hasTriggerAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasTriggerAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestTriggerAccess() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestTriggerAccess');
    } catch (_) {}
  }

  Future<List<InstalledApp>> _android() async {
    final raw = await _channel.invokeListMethod<Map>('list');
    if (raw == null || raw.isEmpty) return _sample();
    final apps = raw
        .map((m) => InstalledApp.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }

  Future<List<InstalledApp>> _windows() async {
    final result = await Process.run('tasklist', ['/fo', 'csv', '/nh']);
    if (result.exitCode != 0) return _sample();
    final seen = <String>{};
    final apps = <InstalledApp>[];
    for (final line in (result.stdout as String).split('\n')) {
      final cols = line.split('","');
      if (cols.isEmpty) continue;
      final image = cols.first.replaceAll('"', '').trim();
      if (!image.toLowerCase().endsWith('.exe')) continue;
      if (!seen.add(image.toLowerCase())) continue;
      final isSystem = _windowsSystem.contains(image.toLowerCase());
      apps.add(
        InstalledApp(
          id: image,
          name: image.replaceAll(RegExp(r'\.exe$', caseSensitive: false), ''),
          isSystem: isSystem,
          hasLauncher: !isSystem,
        ),
      );
    }
    apps.sort((a, b) {
      if (a.isSystem != b.isSystem) return a.isSystem ? 1 : -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return apps.isEmpty ? _sample() : apps;
  }

  static const _windowsSystem = {
    'svchost.exe',
    'system',
    'registry',
    'smss.exe',
    'csrss.exe',
    'wininit.exe',
    'services.exe',
    'lsass.exe',
    'winlogon.exe',
    'dwm.exe',
    'fontdrvhost.exe',
    'sihost.exe',
    'ctfmon.exe',
    'runtimebroker.exe',
  };

  List<InstalledApp> _sample() => const [
    InstalledApp(id: 'org.telegram.messenger', name: 'Telegram'),
    InstalledApp(id: 'com.google.android.youtube', name: 'YouTube'),
    InstalledApp(id: 'com.instagram.android', name: 'Instagram'),
    InstalledApp(id: 'com.whatsapp', name: 'WhatsApp'),
    InstalledApp(id: 'com.discord', name: 'Discord'),
    InstalledApp(id: 'com.spotify.music', name: 'Spotify'),
    InstalledApp(id: 'com.android.chrome', name: 'Chrome'),
    InstalledApp(id: 'com.brave.browser', name: 'Brave'),
    InstalledApp(id: 'com.valvesoftware.steam', name: 'Steam'),
    InstalledApp(id: 'com.epicgames.launcher', name: 'Epic Games'),
    InstalledApp(id: 'com.microsoft.office.outlook', name: 'Outlook'),
    InstalledApp(id: 'ru.yandex.searchplugin', name: 'Яндекс'),
    InstalledApp(id: 'com.vk.im', name: 'VK Мессенджер'),
    InstalledApp(id: 'com.github.desktop', name: 'GitHub Desktop'),
    InstalledApp(id: 'com.figma.desktop', name: 'Figma'),
    InstalledApp(
      id: 'system.android',
      name: 'Системные сервисы',
      isSystem: true,
      hasLauncher: false,
    ),
  ];
}
