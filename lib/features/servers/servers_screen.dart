import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/country_flags.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/proxy_node.dart';
import '../../data/models/subscription.dart';
import '../../state/connection_controller.dart';
import '../../state/profile_controller.dart';
import '../../state/settings_controller.dart';
import '../../widgets/flag_badge.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/ui_bits.dart';
import 'import_sheet.dart';

class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  String _query = '';
  bool _sortByPing = false;

  List<ProxyNode> _filter(List<ProxyNode> src) {
    var nodes = src;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      nodes = nodes
          .where((n) =>
              n.name.toLowerCase().contains(q) ||
              n.server.toLowerCase().contains(q))
          .toList();
    }
    if (_sortByPing) {
      nodes = [...nodes]..sort((a, b) {
          final al = a.latencyMs ?? 1 << 30;
          final bl = b.latencyMs ?? 1 << 30;
          return (al < 0 ? 1 << 29 : al).compareTo(bl < 0 ? 1 << 29 : bl);
        });
    }
    return nodes;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final settings = ref.watch(settingsProvider);
    final activeId = settings.activeNodeId;
    final searching = _query.isNotEmpty;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            children: [
              _topBar(profile),
              if (profile.busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: (profile.subscriptions.isEmpty && profile.nodes.isEmpty)
                    ? EmptyState(
                        icon: Icons.dns_rounded,
                        title: 'Пока пусто',
                        message:
                            'Добавьте подписку или вставьте ссылки на серверы, чтобы начать.',
                        action: AuroraButton(
                          label: 'Добавить',
                          icon: Icons.add_rounded,
                          expand: false,
                          onPressed: () => ImportSheet.show(context),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                        children: [
                          SectionHeader(
                            'Серверы · ${profile.nodes.length}',
                            trailing: _sortToggle(),
                          ),
                          _search(),
                          const SizedBox(height: 12),
                          // Grouped by subscription; each group collapses. When
                          // searching we flatten so nothing hides matches.
                          if (searching)
                            ..._flatResults(profile, activeId)
                          else ...[
                            for (final s in profile.subscriptions)
                              ..._group(s, profile, settings, activeId),
                            if (profile.looseNodes.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const SectionHeader('Свои серверы'),
                              for (final n in _filter(profile.looseNodes))
                                _NodeTile(
                                  node: n,
                                  selected: n.id == activeId,
                                  pinging: profile.pinging.contains(n.id),
                                ),
                            ],
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _flatResults(ProfileState profile, String? activeId) {
    final nodes = _filter(profile.nodes);
    if (nodes.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Text('Ничего не найдено',
              textAlign: TextAlign.center,
              style: AppType.ui(14, color: AppColors.mist)),
        ),
      ];
    }
    return [
      for (final n in nodes)
        _NodeTile(
          node: n,
          selected: n.id == activeId,
          pinging: profile.pinging.contains(n.id),
        ),
    ];
  }

  List<Widget> _group(
      Subscription sub, ProfileState profile, dynamic settings, String? activeId) {
    final collapsed = settings.collapsedSubs.contains(sub.id) as bool;
    final nodes = _filter(profile.nodesOf(sub.id));
    return [
      _SubscriptionCard(sub: sub, collapsed: collapsed),
      if (!collapsed)
        for (final n in nodes)
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: _NodeTile(
              node: n,
              selected: n.id == activeId,
              pinging: profile.pinging.contains(n.id),
            ),
          ),
      const SizedBox(height: 8),
    ];
  }

  Widget _topBar(ProfileState profile) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      child: Row(
        children: [
          Text('Серверы', style: AppType.display(24)),
          const Spacer(),
          IconButton(
            tooltip: 'Быстрейший сервер',
            onPressed: profile.nodes.isEmpty
                ? null
                : () => ref.read(connectionProvider.notifier).connectFastest(),
            icon: const Icon(Icons.bolt_rounded),
            color: AppColors.auroraViolet,
          ),
          IconButton(
            tooltip: 'Проверить пинг',
            onPressed: profile.nodes.isEmpty
                ? null
                : () => ref.read(profileProvider.notifier).pingAll(),
            icon: const Icon(Icons.network_check_rounded),
            color: AppColors.auroraTeal,
          ),
          IconButton(
            tooltip: 'Добавить',
            onPressed: () => ImportSheet.show(context),
            icon: const Icon(Icons.add_circle_outline_rounded),
            color: AppColors.frost,
          ),
        ],
      ),
    );
  }

  Widget _sortToggle() {
    return GestureDetector(
      onTap: () => setState(() => _sortByPing = !_sortByPing),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_vert_rounded,
              size: 15, color: _sortByPing ? AppColors.auroraTeal : AppColors.mist),
          const SizedBox(width: 4),
          Text(_sortByPing ? 'по пингу' : 'по порядку',
              style: AppType.ui(11, weight: FontWeight.w700,
                  color: _sortByPing ? AppColors.auroraTeal : AppColors.mist)),
        ],
      ),
    );
  }

  Widget _search() {
    return TextField(
      onChanged: (v) => setState(() => _query = v),
      style: AppType.ui(14),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Поиск сервера',
        hintStyle: AppType.ui(14, color: AppColors.mistDim),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.mist, size: 20),
        filled: true,
        fillColor: AppColors.abyss,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.auroraTeal, width: 1.3),
        ),
      ),
    );
  }
}

class _SubscriptionCard extends ConsumerWidget {
  const _SubscriptionCard({required this.sub, required this.collapsed});
  final Subscription sub;
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(profileProvider.notifier);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      // Tap the header to collapse/expand this subscription's servers.
      onTap: () => ref.read(settingsProvider.notifier).toggleCollapsedSub(sub.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.expand_more_rounded,
                    color: AppColors.mist, size: 22),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.cloud_sync_rounded,
                  color: AppColors.auroraViolet, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(sub.name,
                    style: AppType.ui(15, weight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.slateHi,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${sub.nodeCount}',
                    style: AppType.mono(11, weight: FontWeight.w700,
                        color: AppColors.mist)),
              ),
              PopupMenuButton<String>(
                color: AppColors.slate,
                icon: const Icon(Icons.more_horiz_rounded, color: AppColors.mist),
                onSelected: (v) {
                  switch (v) {
                    case 'refresh':
                      ctrl.refreshSubscription(sub.id);
                    case 'hide':
                      ref.read(settingsProvider.notifier).toggleCollapsedSub(sub.id);
                    case 'auto':
                      ctrl.toggleAutoUpdate(sub.id);
                    case 'delete':
                      ctrl.removeSubscription(sub.id);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'refresh', child: Text('Обновить')),
                  PopupMenuItem(
                      value: 'hide',
                      child: Text(collapsed ? 'Показать серверы' : 'Скрыть серверы')),
                  PopupMenuItem(
                      value: 'auto',
                      child: Text(sub.autoUpdate
                          ? 'Выключить автообновление'
                          : 'Включить автообновление')),
                  const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _chip('${sub.nodeCount} узлов'),
              const SizedBox(width: 8),
              _chip('обновлено ${Fmt.relative(sub.lastUpdated)}'),
            ],
          ),
          if (sub.hasUsage) ...[
            const SizedBox(height: 14),
            _UsageBar(sub: sub),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text) => Text(text, style: AppType.ui(11.5, color: AppColors.mist));
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: sub.usedFraction,
            minHeight: 6,
            backgroundColor: AppColors.slateHi,
            valueColor: AlwaysStoppedAnimation(
              sub.usedFraction > 0.9 ? AppColors.signalRed : AppColors.auroraTeal,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${Fmt.bytes(sub.usedBytes)} / ${Fmt.bytes(sub.totalBytes)}',
                style: AppType.mono(11, color: AppColors.mist)),
            if (sub.expiresAt != null)
              Text('до ${Fmt.date(sub.expiresAt)}',
                  style: AppType.mono(11, color: AppColors.mist)),
          ],
        ),
      ],
    );
  }
}

class _NodeTile extends ConsumerWidget {
  const _NodeTile({required this.node, required this.selected, this.pinging = false});
  final ProxyNode node;
  final bool selected;
  final bool pinging;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      highlight: selected,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => ref.read(connectionProvider.notifier).connectTo(node),
      child: Row(
        children: [
          FlagBadge(source: node.name, size: 40, selected: selected),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(CountryFlags.cleanName(node.name),
                    style: AppType.ui(14.5, weight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    ProtocolBadge(node.protocol),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('${node.server}:${node.port}',
                          style: AppType.mono(11, color: AppColors.mist),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          LatencyIndicator(node.latencyMs, loading: pinging),
          PopupMenuButton<String>(
            color: AppColors.slate,
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.mistDim, size: 18),
            onSelected: (v) {
              if (v == 'ping') ref.read(profileProvider.notifier).pingNode(node.id);
              if (v == 'delete') ref.read(profileProvider.notifier).removeNode(node.id);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'ping', child: Text('Проверить пинг')),
              PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
        ],
      ),
    );
  }
}
