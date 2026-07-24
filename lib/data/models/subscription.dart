/// A remote subscription URL that yields a list of [ProxyNode]s. Optionally
/// carries traffic/expiry info reported via the `Subscription-Userinfo` header.
class Subscription {
  Subscription({
    required this.id,
    required this.name,
    required this.url,
    required this.addedAt,
    this.lastUpdated,
    this.nodeCount = 0,
    this.autoUpdate = true,
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    this.totalBytes = 0,
    this.expireUnix = 0,
  });

  final String id;
  final String name;
  final String url;
  final DateTime addedAt;
  final DateTime? lastUpdated;
  final int nodeCount;
  final bool autoUpdate;

  // Parsed from `Subscription-Userinfo: upload=..; download=..; total=..; expire=..`.
  final int uploadBytes;
  final int downloadBytes;
  final int totalBytes;
  final int expireUnix;

  int get usedBytes => uploadBytes + downloadBytes;

  double get usedFraction =>
      totalBytes <= 0 ? 0 : (usedBytes / totalBytes).clamp(0.0, 1.0);

  DateTime? get expiresAt => expireUnix > 0
      ? DateTime.fromMillisecondsSinceEpoch(expireUnix * 1000)
      : null;

  bool get hasUsage => totalBytes > 0;

  bool isStale({Duration maxAge = const Duration(minutes: 5), DateTime? now}) {
    final updated = lastUpdated;
    if (updated == null) return true;
    return (now ?? DateTime.now()).difference(updated) >= maxAge;
  }

  Subscription copyWith({
    String? name,
    DateTime? lastUpdated,
    int? nodeCount,
    bool? autoUpdate,
    int? uploadBytes,
    int? downloadBytes,
    int? totalBytes,
    int? expireUnix,
  }) => Subscription(
    id: id,
    name: name ?? this.name,
    url: url,
    addedAt: addedAt,
    lastUpdated: lastUpdated ?? this.lastUpdated,
    nodeCount: nodeCount ?? this.nodeCount,
    autoUpdate: autoUpdate ?? this.autoUpdate,
    uploadBytes: uploadBytes ?? this.uploadBytes,
    downloadBytes: downloadBytes ?? this.downloadBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    expireUnix: expireUnix ?? this.expireUnix,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'addedAt': addedAt.toIso8601String(),
    'lastUpdated': lastUpdated?.toIso8601String(),
    'nodeCount': nodeCount,
    'autoUpdate': autoUpdate,
    'uploadBytes': uploadBytes,
    'downloadBytes': downloadBytes,
    'totalBytes': totalBytes,
    'expireUnix': expireUnix,
  };

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
    id: j['id'] as String,
    name: j['name'] as String,
    url: j['url'] as String,
    addedAt: DateTime.parse(j['addedAt'] as String),
    lastUpdated: j['lastUpdated'] == null
        ? null
        : DateTime.parse(j['lastUpdated'] as String),
    nodeCount: (j['nodeCount'] as num?)?.toInt() ?? 0,
    autoUpdate: j['autoUpdate'] as bool? ?? true,
    uploadBytes: (j['uploadBytes'] as num?)?.toInt() ?? 0,
    downloadBytes: (j['downloadBytes'] as num?)?.toInt() ?? 0,
    totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
    expireUnix: (j['expireUnix'] as num?)?.toInt() ?? 0,
  );
}
