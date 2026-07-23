/// Live traffic counters for the active session.
class ConnectionStats {
  const ConnectionStats({
    this.uploadTotal = 0,
    this.downloadTotal = 0,
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.connectedSince,
  });

  final int uploadTotal; // bytes
  final int downloadTotal; // bytes
  final double uploadSpeed; // bytes/sec
  final double downloadSpeed; // bytes/sec
  final DateTime? connectedSince;

  Duration get sessionDuration => connectedSince == null
      ? Duration.zero
      : DateTime.now().difference(connectedSince!);

  ConnectionStats copyWith({
    int? uploadTotal,
    int? downloadTotal,
    double? uploadSpeed,
    double? downloadSpeed,
    DateTime? connectedSince,
  }) =>
      ConnectionStats(
        uploadTotal: uploadTotal ?? this.uploadTotal,
        downloadTotal: downloadTotal ?? this.downloadTotal,
        uploadSpeed: uploadSpeed ?? this.uploadSpeed,
        downloadSpeed: downloadSpeed ?? this.downloadSpeed,
        connectedSince: connectedSince ?? this.connectedSince,
      );

  static const empty = ConnectionStats();
}
