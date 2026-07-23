import 'package:flutter/material.dart';

/// Aurora palette — a deliberately desaturated indigo night, never pure black,
/// with an aurora gradient (teal → violet → pink) reserved for the *active*
/// connected state. State signals stay legible against the dark surfaces.
class AppColors {
  AppColors._();

  // Surfaces — layered depth from deepest background to raised cards.
  static const Color voidBg = Color(0xFF0A0E1A);
  static const Color abyss = Color(0xFF111726);
  static const Color slate = Color(0xFF1B2436);
  static const Color slateHi = Color(0xFF243049);

  // Text.
  static const Color frost = Color(0xFFE8ECF5);
  static const Color mist = Color(0xFF8B95AD);
  static const Color mistDim = Color(0xFF5A6379);

  // Aurora accent stops — the signature gradient.
  static const Color auroraTeal = Color(0xFF2DD4BF);
  static const Color auroraViolet = Color(0xFF7C6BFF);
  static const Color auroraPink = Color(0xFFFF6FB5);

  // Connection-state signals.
  static const Color signalGreen = Color(0xFF34D399);
  static const Color signalAmber = Color(0xFFFBBF24);
  static const Color signalRed = Color(0xFFFB6A6A);

  // Utility.
  static const Color hairline = Color(0x1AFFFFFF); // 10% white
  static const Color hairlineStrong = Color(0x24FFFFFF);
  static const Color glassFill = Color(0x0DFFFFFF); // 5% white

  static const List<Color> aurora = [auroraTeal, auroraViolet, auroraPink];

  static const LinearGradient auroraGradient = LinearGradient(
    colors: aurora,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const SweepGradient auroraSweep = SweepGradient(
    colors: [auroraTeal, auroraViolet, auroraPink, auroraTeal],
    stops: [0.0, 0.4, 0.7, 1.0],
  );

  /// Maps a latency in ms to a signal color for pings/quality bars.
  static Color latencyColor(int? ms) {
    if (ms == null || ms < 0) return mistDim;
    if (ms < 120) return signalGreen;
    if (ms < 300) return auroraTeal;
    if (ms < 600) return signalAmber;
    return signalRed;
  }
}
