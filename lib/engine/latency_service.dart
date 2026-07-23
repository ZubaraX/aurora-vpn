import 'dart:async';
import 'dart:io';

/// Measures real TCP handshake latency to a proxy endpoint. Works on every
/// platform via dart:io sockets — no core required to rank servers by ping.
class LatencyService {
  const LatencyService();

  Future<int> ping(String host, int port,
      {Duration timeout = const Duration(seconds: 3)}) async {
    if (port <= 0) return -1;
    final sw = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    } finally {
      socket?.destroy();
    }
  }
}
