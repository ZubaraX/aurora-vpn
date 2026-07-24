import 'dart:typed_data';

/// An application the user can include in / exclude from the tunnel.
///
/// On Android [id] is the package name; on Windows it is the executable path.
/// The platform layer supplies these; when no platform bridge is available a
/// curated sample set is shown so the routing UI is fully explorable.
class InstalledApp {
  const InstalledApp({
    required this.id,
    required this.name,
    this.isSystem = false,
    this.hasLauncher = true,
    this.iconBytes,
  });

  final String id;
  final String name;
  final bool isSystem;
  final bool hasLauncher;
  final Uint8List? iconBytes;

  /// A preinstalled launcher app is user-facing even when Android marks its
  /// package with FLAG_SYSTEM. Only background system components are hidden.
  bool get isSystemService => isSystem && !hasLauncher;

  factory InstalledApp.fromJson(Map<String, dynamic> j) => InstalledApp(
    id: j['id'] as String,
    name: j['name'] as String,
    isSystem: j['isSystem'] as bool? ?? false,
    hasLauncher: j['hasLauncher'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isSystem': isSystem,
    'hasLauncher': hasLauncher,
  };
}
