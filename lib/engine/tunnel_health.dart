/// Decides when a *live* tunnel is genuinely dead and worth replacing.
///
/// The traffic probe alone is not trustworthy. Measured on a cellular link, the
/// Clash delay probe timed out repeatedly (a cold dial through the exit costs
/// ~3s: DNS + Reality handshake + TLS) while the same tunnel was serving pages
/// and, at one point, 522 KB/s of download. Acting on those verdicts restarted
/// the core every ~50s, which is what actually broke the connection.
///
/// So a probe failure only counts when nothing is flowing: bytes on the wire
/// are direct proof the exit works and outrank any probe.
class TunnelHealth {
  /// Consecutive failed samples tolerated before switching servers.
  static const failuresBeforeSwitch = 2;

  int _failures = 0;
  int _lastBytes = -1;

  void reset() {
    _failures = 0;
    _lastBytes = -1;
  }

  /// Feeds one health sample; returns true when the server should be replaced.
  ///
  /// [totalBytes] is the session's cumulative up + down counter. It restarts
  /// from zero whenever the core restarts, so only an *increase* counts as
  /// traffic.
  bool sample({required bool probeOk, required int totalBytes}) {
    final moved = _lastBytes >= 0 && totalBytes > _lastBytes;
    _lastBytes = totalBytes;
    if (probeOk || moved) {
      _failures = 0;
      return false;
    }
    return ++_failures >= failuresBeforeSwitch;
  }
}
