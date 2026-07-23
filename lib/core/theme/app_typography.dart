import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type roles for Aurora, backed by bundled variable fonts (no runtime fetch):
/// - [display]  Space Grotesk — headings, status words, big figures.
/// - [ui]       Manrope — body, labels, buttons.
/// - [mono]     JetBrains Mono — latency, throughput, IPs, keys.
///
/// Weight is applied through the `wght` variation axis so a single ttf per
/// family covers every weight we use.
class AppType {
  AppType._();

  static const _display = 'SpaceGrotesk';
  static const _ui = 'Manrope';
  static const _mono = 'JetBrainsMono';

  static TextStyle _style(
    String family,
    double size,
    FontWeight weight,
    Color? color,
    double spacing,
    double height,
  ) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
        color: color ?? AppColors.frost,
        letterSpacing: spacing,
        height: height,
      );

  static TextStyle display(double size,
          {FontWeight weight = FontWeight.w600, Color? color, double? spacing}) =>
      _style(_display, size, weight, color, spacing ?? -0.5, 1.05);

  static TextStyle ui(double size,
          {FontWeight weight = FontWeight.w500,
          Color? color,
          double? spacing,
          double? height}) =>
      _style(_ui, size, weight, color, spacing ?? 0, height ?? 1.35);

  static TextStyle mono(double size,
          {FontWeight weight = FontWeight.w500, Color? color, double? spacing}) =>
      _style(_mono, size, weight, color, spacing ?? 0, 1.1);

  /// Small all-caps eyebrow used for section labels.
  static TextStyle eyebrow({Color? color}) => ui(
        11,
        weight: FontWeight.w700,
        color: color ?? AppColors.mist,
        spacing: 1.6,
      );
}
