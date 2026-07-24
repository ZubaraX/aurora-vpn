/// Bounded reconnect backoff.
///
/// A short first delay recovers from a network handover without making the UI
/// feel stuck. The hard limit prevents a bad profile from waking the VPN core
/// forever in the background.
class ReconnectPolicy {
  ReconnectPolicy({
    List<Duration> delays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ],
  }) : _delays = List.unmodifiable(delays);

  final List<Duration> _delays;
  int _attempt = 0;

  int get attempts => _attempt;

  Duration? nextDelay() {
    if (_attempt >= _delays.length) return null;
    return _delays[_attempt++];
  }

  void reset() => _attempt = 0;
}
