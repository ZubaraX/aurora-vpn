import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/country_flags.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/enums.dart';
import '../../data/models/proxy_node.dart';
import '../../state/connection_controller.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../../widgets/flag_badge.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/ui_bits.dart';
import 'aurora_orb.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final node = ref.watch(activeNodeProvider);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(connectionProvider.notifier);

    ref.listen(connectionProvider.select((s) => s.message), (_, msg) {
      if (msg != null) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(msg)));
        controller.clearMessage();
      }
    });

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              _Header(backend: controller.backendLabel, realCore: controller.isRealCore),
              const SizedBox(height: 24),
              Center(
                child: AuroraOrb(
                  status: conn.status,
                  title: conn.status.title,
                  subtitle: _orbSubtitle(conn.status, node),
                  onTap: controller.toggle,
                ),
              ),
              const SizedBox(height: 24),
              if (conn.status == ConnectionStatus.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ErrorBanner(
                    message: controller.lastError,
                    onRetry: controller.connect,
                  ),
                ),
              _ServerChip(node: node),
              const SizedBox(height: 14),
              _StatsPanel(status: conn.status, stats: conn.stats, node: node),
              const SizedBox(height: 14),
              _RoutingRow(mode: settings.routingMode),
            ],
          ),
        ),
      ),
    );
  }

  String _orbSubtitle(ConnectionStatus status, ProxyNode? node) => switch (status) {
        ConnectionStatus.connected => 'через ${node?.name ?? 'узел'}',
        ConnectionStatus.connecting => 'устанавливаем защищённый канал',
        ConnectionStatus.disconnecting => 'закрываем туннель',
        ConnectionStatus.error => 'нажмите, чтобы повторить',
        ConnectionStatus.disconnected =>
          node == null ? 'выберите сервер' : 'нажмите, чтобы подключиться',
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.backend, required this.realCore});
  final String backend;
  final bool realCore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ShaderMask(
          shaderCallback: (r) => AppColors.auroraGradient.createShader(r),
          child: Text('Aurora',
              style: AppType.display(26, weight: FontWeight.w700, color: Colors.white)),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (realCore ? AppColors.signalGreen : AppColors.signalAmber)
                .withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            realCore ? 'CORE' : 'DEMO',
            style: AppType.mono(9, weight: FontWeight.w700,
                color: realCore ? AppColors.signalGreen : AppColors.signalAmber),
          ),
        ),
        const Spacer(),
        Text('sing-box', style: AppType.mono(11, color: AppColors.mistDim)),
      ],
    );
  }
}

class _ServerChip extends ConsumerWidget {
  const _ServerChip({required this.node});
  final ProxyNode? node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      onTap: () => ref.read(navIndexProvider.notifier).state = 1,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          node == null
              ? Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: AppColors.auroraGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.public_rounded,
                      color: AppColors.voidBg, size: 22),
                )
              : FlagBadge(source: node!.name, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Текущий сервер', style: AppType.ui(11, color: AppColors.mist)),
                const SizedBox(height: 3),
                Text(
                  node == null ? 'Не выбран' : CountryFlags.cleanName(node!.name),
                  style: AppType.ui(15, weight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (node != null) LatencyIndicator(node!.latencyMs, compact: true),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: AppColors.mist),
        ],
      ),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.status, required this.stats, required this.node});
  final ConnectionStatus status;
  final dynamic stats; // ConnectionStats
  final ProxyNode? node;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        children: [
          Expanded(
            child: MetricTile(
              icon: Icons.south_rounded,
              value: Fmt.speed(stats.downloadSpeed),
              label: 'Загрузка',
              color: AppColors.auroraTeal,
            ),
          ),
          _divider(),
          Expanded(
            child: MetricTile(
              icon: Icons.north_rounded,
              value: Fmt.speed(stats.uploadSpeed),
              label: 'Отдача',
              color: AppColors.auroraViolet,
            ),
          ),
          _divider(),
          Expanded(
            child: MetricTile(
              icon: Icons.timer_outlined,
              value: Fmt.duration(stats.sessionDuration),
              label: 'Сессия',
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: AppColors.hairline,
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        color: AppColors.signalRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.signalRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.signalRed, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message ?? 'Не удалось подключиться. Повторите попытку.',
              style: AppType.ui(12.5, color: AppColors.frost, height: 1.3),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.signalRed,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text('Повторить', style: AppType.ui(13, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _RoutingRow extends ConsumerWidget {
  const _RoutingRow({required this.mode});
  final RoutingMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      onTap: () => ref.read(navIndexProvider.notifier).state = 3,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Row(
        children: [
          const Icon(Icons.alt_route_rounded, color: AppColors.auroraTeal, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Маршрутизация', style: AppType.ui(11, color: AppColors.mist)),
                const SizedBox(height: 3),
                Text(mode.title, style: AppType.ui(14, weight: FontWeight.w700)),
              ],
            ),
          ),
          const Icon(Icons.tune_rounded, color: AppColors.mist, size: 18),
        ],
      ),
    );
  }
}
