import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Ambient backdrop: two soft aurora blooms bleeding from the top corners over
/// the void. Static and cheap — the motion budget belongs to the orb.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.voidBg),
      child: Stack(
        children: [
          Positioned(
            top: -160,
            left: -120,
            child: _bloom(AppColors.auroraViolet.withValues(alpha: 0.22), 360),
          ),
          Positioned(
            top: -80,
            right: -140,
            child: _bloom(AppColors.auroraTeal.withValues(alpha: 0.16), 320),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }

  Widget _bloom(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
