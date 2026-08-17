import 'package:aurora/engine/tunnel_health.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TunnelHealth', () {
    test('a passing probe never switches', () {
      final health = TunnelHealth();
      for (var i = 0; i < 5; i++) {
        expect(health.sample(probeOk: true, totalBytes: 1000), isFalse);
      }
    });

    test('two failed probes on an idle tunnel switch servers', () {
      final health = TunnelHealth();
      expect(health.sample(probeOk: false, totalBytes: 1000), isFalse);
      expect(health.sample(probeOk: false, totalBytes: 1000), isTrue);
    });

    test('a failed probe never switches while bytes are still moving', () {
      // Measured on a live cellular tunnel: the Clash delay probe timed out
      // while the very same tunnel carried 522 KB/s. Traffic is proof the exit
      // works, so it must outrank the probe.
      final health = TunnelHealth();
      health.sample(probeOk: true, totalBytes: 1000);
      for (var i = 1; i <= 6; i++) {
        expect(
          health.sample(probeOk: false, totalBytes: 1000 + i * 500000),
          isFalse,
          reason: 'sample $i carried traffic',
        );
      }
    });

    test('traffic that stops after moving still switches', () {
      final health = TunnelHealth();
      health.sample(probeOk: false, totalBytes: 5000);
      expect(health.sample(probeOk: false, totalBytes: 9000), isFalse);
      expect(health.sample(probeOk: false, totalBytes: 9000), isFalse);
      expect(health.sample(probeOk: false, totalBytes: 9000), isTrue);
    });

    test('counters resetting after a core restart is not traffic', () {
      final health = TunnelHealth();
      health.sample(probeOk: true, totalBytes: 800000);
      // The core restarted: totals start from zero again.
      expect(health.sample(probeOk: false, totalBytes: 0), isFalse);
      expect(health.sample(probeOk: false, totalBytes: 0), isTrue);
    });

    test('reset clears the failure streak', () {
      final health = TunnelHealth();
      health.sample(probeOk: false, totalBytes: 100);
      health.reset();
      expect(health.sample(probeOk: false, totalBytes: 100), isFalse);
    });
  });
}
