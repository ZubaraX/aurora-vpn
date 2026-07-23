import 'dart:io';

import 'android_engine.dart';
import 'simulated_engine.dart';
import 'vpn_engine.dart';
import 'windows_engine.dart';

/// Selects the best available tunnel backend for the current platform,
/// gracefully degrading to the simulation when no real core is present.
class EngineFactory {
  const EngineFactory._();

  static Future<VpnEngine> create() async {
    if (Platform.isWindows) {
      final core = await WindowsProcessEngine.findCore();
      if (core != null) return WindowsProcessEngine(core);
      return SimulatedEngine();
    }
    if (Platform.isAndroid) {
      if (await AndroidVpnEngine.available()) return AndroidVpnEngine();
      return SimulatedEngine();
    }
    return SimulatedEngine();
  }
}
