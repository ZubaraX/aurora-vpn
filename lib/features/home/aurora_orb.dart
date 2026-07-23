import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/enums.dart';

/// The Aurora orb — the app's one loud element.
///
/// A breathing, rotating conic-gradient ring whose color and motion encode the
/// tunnel state: faint slate when idle, an amber comet while connecting, the
/// full teal→violet→pink aurora when connected, red on error. State changes are
/// eased — the accent color lerps and the status label cross-fades — so a
/// reconnect reads as one smooth transition rather than a hard cut. Tapping the
/// orb is the primary connect / disconnect action. Motion honours the
/// platform's reduced-motion setting.
class AuroraOrb extends StatefulWidget {
  const AuroraOrb({
    super.key,
    required this.status,
    required this.onTap,
    required this.title,
    required this.subtitle,
    this.size = 264,
  });

  final ConnectionStatus status;
  final VoidCallback onTap;
  final String title;
  final String subtitle;
  final double size;

  @override
  State<AuroraOrb> createState() => _AuroraOrbState();
}

class _AuroraOrbState extends State<AuroraOrb> with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..repeat();
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat(reverse: true);
  // Eases the accent color from the previous state to the current one.
  late final AnimationController _fade = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520), value: 1);

  late Color _fromAccent = _accentFor(widget.status);
  late Color _toAccent = _fromAccent;
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant AuroraOrb old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) {
      _fromAccent = _currentAccent();
      _toAccent = _accentFor(widget.status);
      _fade.forward(from: 0);

      final target = widget.status == ConnectionStatus.connecting
          ? const Duration(milliseconds: 1300)
          : const Duration(seconds: 8);
      if (_spin.duration != target) {
        _spin
          ..duration = target
          ..repeat();
      }
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    _fade.dispose();
    super.dispose();
  }

  Color _accentFor(ConnectionStatus s) => switch (s) {
        ConnectionStatus.connected => AppColors.signalGreen,
        ConnectionStatus.connecting => AppColors.signalAmber,
        ConnectionStatus.disconnecting => AppColors.signalAmber,
        ConnectionStatus.error => AppColors.signalRed,
        ConnectionStatus.disconnected => AppColors.mist,
      };

  Color _currentAccent() => Color.lerp(
        _fromAccent,
        _toAccent,
        Curves.easeInOut.transform(_fade.value),
      )!;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_spin, _pulse, _fade]),
            builder: (context, _) {
              final accent = _currentAccent();
              return CustomPaint(
                painter: _OrbPainter(
                  status: widget.status,
                  accent: accent,
                  spin: reduceMotion ? 0 : _spin.value,
                  pulse: reduceMotion ? 0.5 : _pulse.value,
                ),
                child: Center(child: _core(accent)),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _core(Color accent) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.14), end: Offset.zero)
              .animate(anim),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey(widget.status),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.status.icon, size: 40, color: accent),
          const SizedBox(height: 14),
          Text(widget.title,
              style: AppType.display(23, color: AppColors.frost),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          SizedBox(
            width: widget.size * 0.62,
            child: Text(
              widget.subtitle,
              style: AppType.ui(12.5, color: AppColors.mist),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.status,
    required this.accent,
    required this.spin,
    required this.pulse,
  });

  final ConnectionStatus status;
  final Color accent;
  final double spin;
  final double pulse;

  bool get _connected => status == ConnectionStatus.connected;
  bool get _working =>
      status == ConnectionStatus.connecting ||
      status == ConnectionStatus.disconnecting;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final ringRadius = radius - 18;

    // 1. Ambient glow — intensity breathes with the pulse.
    final glowStrength = (_connected ? 0.55 : 0.28) * (0.6 + pulse * 0.4);
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..color = accent.withValues(alpha: glowStrength)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 42),
    );

    // 2. Inner disc.
    canvas.drawCircle(
      center,
      ringRadius - 6,
      Paint()
        ..shader = const RadialGradient(
          colors: [AppColors.slate, AppColors.voidBg],
          stops: [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: ringRadius)),
    );

    // 3. Track ring.
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = AppColors.slateHi.withValues(alpha: 0.7),
    );

    // 4. Active ring.
    final rect = Rect.fromCircle(center: center, radius: ringRadius);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    if (_connected) {
      ringPaint.shader = SweepGradient(
        transform: GradientRotation(spin * 2 * math.pi),
        colors: const [
          AppColors.auroraTeal,
          AppColors.auroraViolet,
          AppColors.auroraPink,
          AppColors.auroraTeal,
        ],
        stops: const [0.0, 0.4, 0.7, 1.0],
      ).createShader(rect);
      canvas.drawArc(rect, 0, 2 * math.pi, false, ringPaint);
    } else if (_working) {
      // Amber comet sweeping around the track.
      final start = spin * 2 * math.pi;
      ringPaint.shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        transform: GradientRotation(start),
        colors: [accent.withValues(alpha: 0), accent],
        stops: const [0.72, 1.0],
      ).createShader(rect);
      canvas.drawArc(rect, start, math.pi * 0.75, false, ringPaint);
    } else {
      // Idle: a short static accent arc hinting at the ring.
      ringPaint.color = accent.withValues(alpha: 0.4);
      canvas.drawArc(rect, -math.pi / 2, math.pi * 0.16, false, ringPaint);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.spin != spin ||
      old.pulse != pulse ||
      old.status != status ||
      old.accent != accent;
}
