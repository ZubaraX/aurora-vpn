import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// The single Aurora theme — a dark, desaturated-indigo surface system with
/// the aurora accent reserved for active states. Light mode intentionally
/// isn't offered; the identity is nocturnal by design.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.auroraTeal,
      onPrimary: AppColors.voidBg,
      secondary: AppColors.auroraViolet,
      surface: AppColors.abyss,
      onSurface: AppColors.frost,
      error: AppColors.signalRed,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.voidBg,
      canvasColor: AppColors.voidBg,
      // Use the CPU-backed ripple. Some release APK builds do not package
      // Flutter's optional ink_sparkle shader, which otherwise produces an
      // unhandled exception on the first tap.
      splashFactory: InkRipple.splashFactory,
      splashColor: AppColors.auroraTeal.withValues(alpha: 0.06),
      highlightColor: Colors.transparent,
      dividerColor: AppColors.hairline,
      textTheme: TextTheme(
        displayLarge: AppType.display(40),
        headlineMedium: AppType.display(26),
        titleLarge: AppType.display(20),
        titleMedium: AppType.ui(16, weight: FontWeight.w700),
        bodyLarge: AppType.ui(15),
        bodyMedium: AppType.ui(14, color: AppColors.mist),
        labelLarge: AppType.ui(14, weight: FontWeight.w700),
        labelSmall: AppType.eyebrow(),
      ),
      iconTheme: const IconThemeData(color: AppColors.frost),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.slateHi,
        contentTextStyle: AppType.ui(14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.abyss,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.abyss,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.voidBg
              : AppColors.mist,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.auroraTeal
              : AppColors.slateHi,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
