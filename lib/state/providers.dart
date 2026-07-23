import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/update/update_service.dart';
import '../data/local/storage.dart';
import '../data/parsers/subscription_parser.dart';
import '../engine/app_inventory.dart';
import '../engine/latency_service.dart';
import '../engine/vpn_engine.dart';

/// Overridden in main() once SharedPreferences has been initialised.
final storageProvider = Provider<Storage>(
  (ref) => throw UnimplementedError('storageProvider must be overridden'),
);

/// Overridden in main() with the platform-appropriate engine.
final engineProvider = Provider<VpnEngine>(
  (ref) => throw UnimplementedError('engineProvider must be overridden'),
);

final latencyServiceProvider = Provider((ref) => const LatencyService());
final appInventoryProvider = Provider((ref) => const AppInventory());
final subscriptionParserProvider = Provider((ref) => const SubscriptionParser());
final updateServiceProvider = Provider((ref) => const UpdateService());

/// Selected bottom-nav / rail destination, shared so any screen can navigate.
final navIndexProvider = StateProvider<int>((ref) => 0);
