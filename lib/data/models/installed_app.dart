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
    this.iconBytes,
  });

  final String id;
  final String name;
  final bool isSystem;
  final Uint8List? iconBytes;

  factory InstalledApp.fromJson(Map<String, dynamic> j) => InstalledApp(
        id: j['id'] as String,
        name: j['name'] as String,
        isSystem: j['isSystem'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'isSystem': isSystem};
}
