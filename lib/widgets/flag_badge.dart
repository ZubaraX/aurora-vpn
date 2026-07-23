import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/country_flags.dart';

/// A rounded badge showing the country flag inferred from a server name,
/// rendered via the bundled Twemoji color font. Falls back to a globe glyph
/// when the country can't be determined.
class FlagBadge extends StatelessWidget {
  const FlagBadge({
    super.key,
    required this.source,
    this.size = 42,
    this.selected = false,
  });

  final String source;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final emoji = CountryFlags.flagEmoji(source);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.slateHi,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: selected ? AppColors.auroraTeal : AppColors.hairline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: emoji == null
          ? Icon(Icons.public_rounded, size: size * 0.5, color: AppColors.mist)
          : Text(
              emoji,
              style: TextStyle(
                fontFamily: 'Twemoji',
                fontSize: size * 0.62,
                height: 1,
              ),
            ),
    );
  }
}
