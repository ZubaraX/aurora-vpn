import 'package:aurora/engine/reconnect_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconnect backoff is bounded and resets after success', () {
    final policy = ReconnectPolicy();

    expect(policy.nextDelay(), const Duration(seconds: 2));
    expect(policy.nextDelay(), const Duration(seconds: 5));
    expect(policy.nextDelay(), const Duration(seconds: 10));
    expect(policy.nextDelay(), isNull);

    policy.reset();
    expect(policy.attempts, 0);
    expect(policy.nextDelay(), const Duration(seconds: 2));
  });

  test('custom reconnect schedule preserves order', () {
    final policy = ReconnectPolicy(
      delays: const [Duration(milliseconds: 50), Duration(milliseconds: 100)],
    );

    expect(policy.nextDelay(), const Duration(milliseconds: 50));
    expect(policy.nextDelay(), const Duration(milliseconds: 100));
    expect(policy.nextDelay(), isNull);
  });
}
