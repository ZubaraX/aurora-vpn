import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../data/models/enums.dart';

/// Small all-caps section label with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Row(
        children: [
          Expanded(child: Text(label.toUpperCase(), style: AppType.eyebrow())),
          ?trailing,
        ],
      ),
    );
  }
}

/// Protocol chip (VLESS / HY2 / …) tinted by protocol family.
class ProtocolBadge extends StatelessWidget {
  const ProtocolBadge(this.protocol, {super.key});
  final ProxyProtocol protocol;

  Color get _tint => switch (protocol) {
        ProxyProtocol.vless || ProxyProtocol.vmess => AppColors.auroraViolet,
        ProxyProtocol.trojan => AppColors.auroraPink,
        ProxyProtocol.shadowsocks => AppColors.auroraTeal,
        ProxyProtocol.hysteria2 || ProxyProtocol.tuic => AppColors.signalAmber,
        ProxyProtocol.wireguard => AppColors.signalGreen,
        _ => AppColors.mist,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _tint.withValues(alpha: 0.35)),
      ),
      child: Text(
        protocol.badge,
        style: AppType.mono(10, weight: FontWeight.w700, color: _tint),
      ),
    );
  }
}

/// Colored dot + latency text for a node's measured ping.
class LatencyIndicator extends StatelessWidget {
  const LatencyIndicator(this.ms, {super.key, this.compact = false});
  final int? ms;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.latencyColor(ms);
    final value = ms;
    final text = value == null
        ? '—'
        : value < 0
            ? 'таймаут'
            : '$value ms';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 6),
          Text(text, style: AppType.mono(11, color: color)),
        ],
      ],
    );
  }
}

/// Primary aurora-gradient action button.
class AuroraButton extends StatelessWidget {
  const AuroraButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final child = Container(
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: enabled ? AppColors.auroraGradient : null,
        color: enabled ? null : AppColors.slateHi,
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.auroraViolet.withValues(alpha: 0.35),
                  blurRadius: 22,
                  spreadRadius: -4,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: AppColors.voidBg),
            const SizedBox(width: 10),
          ],
          Text(label,
              style: AppType.ui(15,
                  weight: FontWeight.w800, color: AppColors.voidBg)),
        ],
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: expand ? SizedBox(width: double.infinity, child: child) : child,
      ),
    );
  }
}

/// A compact labelled metric used in stat rows.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.frost;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: c.withValues(alpha: 0.85)),
        const SizedBox(height: 10),
        Text(value, style: AppType.mono(16, weight: FontWeight.w700, color: c)),
        const SizedBox(height: 3),
        Text(label, style: AppType.ui(11, color: AppColors.mist)),
      ],
    );
  }
}

/// Full-width empty-state prompt.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.slate,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hairline),
              ),
              child: Icon(icon, size: 34, color: AppColors.mist),
            ),
            const SizedBox(height: 20),
            Text(title, style: AppType.display(19), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message,
                style: AppType.ui(14, color: AppColors.mist),
                textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 22), action!],
          ],
        ),
      ),
    );
  }
}
