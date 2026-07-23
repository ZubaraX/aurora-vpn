import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// A raised surface with a hairline edge and a whisper of top-light gradient —
/// the standard container for everything that isn't the Aurora orb.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.onTap,
    this.borderColor,
    this.radius = 22,
    this.highlight = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double radius;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final border = borderColor ??
        (highlight ? AppColors.auroraTeal.withValues(alpha: 0.5) : AppColors.hairline);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.slate.withValues(alpha: highlight ? 0.9 : 0.7),
            AppColors.abyss,
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: highlight ? 1.4 : 1),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: AppColors.auroraViolet.withValues(alpha: 0.18),
                  blurRadius: 28,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.auroraTeal.withValues(alpha: 0.05),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
