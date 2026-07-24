import 'package:aurora/data/models/subscription.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 24, 12);

  Subscription subscription(DateTime? lastUpdated) => Subscription(
    id: 'sub',
    name: 'Test',
    url: 'https://example.com/sub',
    addedAt: now.subtract(const Duration(days: 1)),
    lastUpdated: lastUpdated,
  );

  test('never-refreshed subscription is stale', () {
    expect(subscription(null).isStale(now: now), isTrue);
  });

  test('subscription refresh uses the configured freshness window', () {
    final sub = subscription(now.subtract(const Duration(minutes: 3)));

    expect(sub.isStale(maxAge: const Duration(minutes: 2), now: now), isTrue);
    expect(sub.isStale(maxAge: const Duration(minutes: 5), now: now), isFalse);
  });
}
