import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/country_flags.dart';
import '../../data/models/enums.dart';
import '../../data/models/proxy_node.dart';
import '../../state/connection_controller.dart';
import '../../state/profile_controller.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/ui_bits.dart';
import '../logs/diagnostics_screen.dart';
import '../logs/logs_screen.dart';
import '../update/update_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final conn = ref.read(connectionProvider.notifier);
    // Everything that ends up in the generated config must reach the RUNNING
    // core too. Without this a toggle only took effect after a manual
    // reconnect, which is why "Блокировка рекламы" looked like it did nothing:
    // the switch was on while the live config had no reject rule at all.
    void applied(VoidCallback change) {
      change();
      conn.reapply();
    }

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
            children: [
              Text('Настройки', style: AppType.display(24)),
              const SizedBox(height: 20),

              const SectionHeader('Маршрутизация'),
              for (final m in RoutingMode.values)
                _RoutingCard(
                  mode: m,
                  selected: s.routingMode == m,
                  onTap: () => applied(() => ctrl.setRoutingMode(m)),
                ),
              const SizedBox(height: 20),

              const SectionHeader('Доменные зоны'),
              const _DomainZonesCard(),
              const SizedBox(height: 20),

              const SectionHeader('Туннель'),
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _SwitchTile(
                      icon: Icons.vpn_lock_rounded,
                      title: 'Режим TUN',
                      subtitle: 'Перехват всего трафика на уровне системы',
                      value: s.tunMode,
                      onChanged: (v) => applied(() => ctrl.setTunMode(v)),
                    ),
                    _tileDivider(),
                    _StackTile(
                      stack: s.tunStack,
                      onPick: (v) => applied(() => ctrl.setTunStack(v)),
                    ),
                    _tileDivider(),
                    _SwitchTile(
                      icon: Icons.lan_rounded,
                      title: 'Обход локальной сети',
                      subtitle: 'Приватные адреса идут напрямую',
                      value: s.bypassLan,
                      onChanged: (v) => applied(() => ctrl.setBypassLan(v)),
                    ),
                    _tileDivider(),
                    _SwitchTile(
                      icon: Icons.block_rounded,
                      title: 'Блокировка рекламы',
                      subtitle: 'Правило geosite-ads → reject',
                      value: s.blockAds,
                      onChanged: (v) => applied(() => ctrl.setBlockAds(v)),
                    ),
                    _tileDivider(),
                    _SwitchTile(
                      icon: Icons.wifi_tethering_rounded,
                      title: 'Раздача через точку доступа',
                      subtitle: s.lanProxy
                          ? 'Прокси на порту ${s.lanProxyPort}. На клиенте укажите '
                                'адрес этого устройства и этот порт вручную'
                          : 'Устройства из точки доступа смогут выходить через VPN '
                                'по прокси. Доступен всем в этой сети',
                      value: s.lanProxy,
                      onChanged: (v) => applied(() => ctrl.setLanProxy(v)),
                    ),
                    if (s.lanProxy) _LanProxyHint(port: s.lanProxyPort),
                    _tileDivider(),
                    _SwitchTile(
                      icon: Icons.public_rounded,
                      title: 'IPv6',
                      subtitle: 'Двойной стек в туннеле',
                      value: s.ipv6,
                      onChanged: (v) => applied(() => ctrl.setIpv6(v)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const SectionHeader('Безопасность'),
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _SwitchTile(
                      icon: Icons.shield_moon_rounded,
                      title: 'Kill Switch',
                      subtitle: 'Блокировать трафик при обрыве туннеля',
                      value: s.killSwitch,
                      onChanged: ctrl.setKillSwitch,
                    ),
                    _tileDivider(),
                    _SwitchTile(
                      icon: Icons.play_circle_outline_rounded,
                      title: 'Автоподключение',
                      subtitle: 'Подключаться при запуске приложения',
                      value: s.autoConnect,
                      onChanged: ctrl.setAutoConnect,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const SectionHeader('DNS'),
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _EditTile(
                      icon: Icons.dns_rounded,
                      title: 'DNS через прокси',
                      value: s.dnsRemote,
                      onSave: (v) => applied(() => ctrl.setDnsRemote(v)),
                    ),
                    _tileDivider(),
                    _EditTile(
                      icon: Icons.router_rounded,
                      title: 'DNS напрямую',
                      value: s.dnsDirect,
                      onSave: (v) => applied(() => ctrl.setDnsDirect(v)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const SectionHeader('О приложении'),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('Ядро', conn.backendLabel),
                    const SizedBox(height: 10),
                    _infoRow(
                      'Статус ядра',
                      conn.isRealCore ? 'Активно' : 'Симуляция',
                    ),
                    const SizedBox(height: 10),
                    _infoRow('Версия', 'Aurora $kAppVersion'),
                    const SizedBox(height: 14),
                    Text(
                      'Aurora — универсальный клиент на базе sing-box. '
                      'Поддерживает VLESS, VMess, Trojan, Shadowsocks, Hysteria2, TUIC и WireGuard.',
                      style: AppType.ui(12.5, color: AppColors.mist),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (Platform.isAndroid) ...[
                      _NavRow(
                        icon: Icons.dashboard_customize_rounded,
                        title: 'Добавить кнопку VPN в шторку',
                        onTap: () => _addQuickTile(context),
                      ),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.hairline,
                        indent: 56,
                      ),
                    ],
                    _NavRow(
                      icon: Icons.system_update_rounded,
                      title: 'Проверить обновления',
                      onTap: () => _checkUpdate(context, ref),
                    ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.hairline,
                      indent: 56,
                    ),
                    _NavRow(
                      icon: Icons.health_and_safety_outlined,
                      title: 'Диагностика',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DiagnosticsScreen(),
                        ),
                      ),
                    ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.hairline,
                      indent: 56,
                    ),
                    _NavRow(
                      icon: Icons.article_outlined,
                      title: 'Логи',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LogsScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _checkUpdate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Проверяем обновления…')),
    );
    final info = await ref.read(updateServiceProvider).check();
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    if (info == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('У вас последняя версия')),
      );
    } else {
      showUpdateDialog(context, info);
    }
  }

  Future<void> _addQuickTile(BuildContext context) async {
    const channel = MethodChannel('aurora/vpn');
    final messenger = ScaffoldMessenger.of(context);
    try {
      final status =
          await channel.invokeMethod<String>('addQuickTile') ?? 'error';
      if (!context.mounted) return;
      final message = switch (status) {
        'added' => 'Кнопка Aurora добавлена в шторку',
        'already_added' => 'Кнопка Aurora уже находится в шторке',
        'not_added' => 'Добавление кнопки отменено',
        'manual' =>
          'Откройте шторку, нажмите «Изменить» и перетащите Aurora VPN',
        _ => 'Не удалось добавить кнопку Aurora',
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on PlatformException {
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось добавить кнопку Aurora')),
      );
    }
  }

  Widget _tileDivider() => const Divider(
    height: 1,
    thickness: 1,
    color: AppColors.hairline,
    indent: 56,
  );

  Widget _infoRow(String k, String v) => Row(
    children: [
      Text(k, style: AppType.ui(13, color: AppColors.mist)),
      const Spacer(),
      Flexible(
        child: Text(
          v,
          style: AppType.mono(12, color: AppColors.frost),
          textAlign: TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// User routing rules by domain zone (e.g. `.ru → напрямую`).
/// Shows the addresses a hotspot client should point its proxy at. The hotspot
/// gateway gets a fresh address every session (172.28.x.x, 192.168.43.x, …), so
/// printing the live list beats telling the user to go hunting for it.
class _LanProxyHint extends StatelessWidget {
  const _LanProxyHint({required this.port});
  final int port;

  Future<List<String>> _addresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      return [
        for (final i in interfaces)
          for (final a in i.addresses)
            // Skip our own TUN: a client can never reach that address.
            if (!a.address.startsWith('172.19.0.')) '${a.address}:$port',
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _addresses(),
      builder: (context, snap) {
        final list = snap.data ?? const <String>[];
        return Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                list.isEmpty
                    ? 'Адрес появится, когда точка доступа заработает'
                    : 'Укажите на клиенте (HTTP или SOCKS5):',
                style: AppType.ui(11.5, color: AppColors.mistDim),
              ),
              for (final a in list) ...[
                const SizedBox(height: 4),
                SelectableText(
                  a,
                  style: AppType.mono(12.5, color: AppColors.auroraTeal),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DomainZonesCard extends ConsumerStatefulWidget {
  const _DomainZonesCard();

  @override
  ConsumerState<_DomainZonesCard> createState() => _DomainZonesCardState();
}

class _DomainZonesCardState extends ConsumerState<_DomainZonesCard> {
  /// Zones ticked for a bulk target change.
  final Set<String> _selected = {};

  static const _targets = {
    'direct': ('Напрямую', AppColors.auroraTeal),
    'proxy': ('Через VPN', AppColors.auroraViolet),
    'block': ('Блок', AppColors.signalRed),
  };
  static const _presets = ['ru', 'рф', 'by', 'com', 'cn'];

  /// Ready-made profile for users in Russia: local resources go DIRECT (many
  /// reject foreign IPs and are simply faster that way), services that are
  /// blocked locally go through the VPN. Applied on top of existing rules.
  static const _russiaPreset = <String, String>{
    // Local zones and Russian services hosted outside .ru
    'ru': 'direct',
    'рф': 'direct',
    'su': 'direct',
    'vk.com': 'direct',
    'userapi.com': 'direct',
    'vk-cdn.net': 'direct',
    'vkuser.net': 'direct',
    'mycdn.me': 'direct',
    'yandex.net': 'direct',
    'yandex.com': 'direct',
    'yastatic.net': 'direct',
    '2gis.com': 'direct',
    'sberbank.com': 'direct',
    'gosuslugi.net': 'direct',
    'wildberries.am': 'direct',
    // Blocked or throttled locally — route through the tunnel
    'youtube.com': 'proxy',
    'youtu.be': 'proxy',
    'googlevideo.com': 'proxy',
    'ytimg.com': 'proxy',
    'ggpht.com': 'proxy',
    'instagram.com': 'proxy',
    'cdninstagram.com': 'proxy',
    'facebook.com': 'proxy',
    'fbcdn.net': 'proxy',
    'twitter.com': 'proxy',
    'x.com': 'proxy',
    'twimg.com': 'proxy',
    'discord.com': 'proxy',
    'discord.gg': 'proxy',
    'discordapp.net': 'proxy',
    'linkedin.com': 'proxy',
    'soundcloud.com': 'proxy',
    'openai.com': 'proxy',
    'chatgpt.com': 'proxy',
    'claude.ai': 'proxy',
    'anthropic.com': 'proxy',
    'medium.com': 'proxy',
    'notion.so': 'proxy',
  };

  /// One-tap ad/tracker zones for the Доменные зоны list. The global
  /// "Блокировка рекламы" switch already rejects ~187k hosts from the bundled
  /// rule-set; these are the few networks worth having as VISIBLE, editable
  /// rules — so they can be seen, and individually switched back to direct if
  /// something a user needs turns out to depend on one.
  static const _adsPreset = <String, String>{
    'doubleclick.net': 'block',
    'googlesyndication.com': 'block',
    'googleadservices.com': 'block',
    'google-analytics.com': 'block',
    'googletagmanager.com': 'block',
    'googletagservices.com': 'block',
    'adservice.google.com': 'block',
    'app-measurement.com': 'block',
    'crashlytics.com': 'block',
    'adcolony.com': 'block',
    'applovin.com': 'block',
    'unityads.unity3d.com': 'block',
    'chartboost.com': 'block',
    'vungle.com': 'block',
    'inmobi.com': 'block',
    'mopub.com': 'block',
    'smaato.net': 'block',
    'criteo.com': 'block',
    'outbrain.com': 'block',
    'taboola.com': 'block',
    'scorecardresearch.com': 'block',
    'hotjar.com': 'block',
    'amplitude.com': 'block',
    'appsflyer.com': 'block',
    'adjust.com': 'block',
    'branch.io': 'block',
    'flurry.com': 'block',
    'adriver.ru': 'block',
    'adfox.ru': 'block',
    'admob.com': 'block',
  };

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(settingsProvider).domainZoneRules;
    final nodes = ref.watch(profileProvider).nodes;
    final ctrl = ref.read(settingsProvider.notifier);
    final entries = rules.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    // Drop selections whose zone was removed since.
    _selected.removeWhere((z) => !rules.containsKey(z));

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Отправляйте домены определённой зоны напрямую, через VPN, '
            'через конкретный сервер или блокируйте их. Например, зона «ru» — '
            'все сайты *.ru.',
            style: AppType.ui(12.5, color: AppColors.mist),
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    // Tick to include this zone in a bulk target change.
                    GestureDetector(
                      onTap: () => setState(() {
                        _selected.contains(e.key)
                            ? _selected.remove(e.key)
                            : _selected.add(e.key);
                      }),
                      child: _tick(_selected.contains(e.key)),
                    ),
                    const SizedBox(width: 10),
                    // The zone name yields space to the target chip, so the
                    // target label ("Напрямую"/"Через VPN"/server) stays legible
                    // instead of being clipped to "Напрям…".
                    Expanded(
                      child: Text(
                        '.${e.key}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.mono(13, weight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Tap the target to change where this zone goes.
                    GestureDetector(
                      onTap: () =>
                          _showEditTarget(context, ref, e.key, e.value, nodes),
                      child: _targetChip(e.value, nodes),
                    ),
                    IconButton(
                      tooltip: 'Изменить',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.edit_rounded,
                        color: AppColors.mistDim,
                        size: 17,
                      ),
                      onPressed: () =>
                          _showEditTarget(context, ref, e.key, e.value, nodes),
                    ),
                    IconButton(
                      tooltip: 'Удалить',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.mistDim,
                        size: 18,
                      ),
                      onPressed: () {
                        ctrl.removeDomainZoneRule(e.key);
                        ref.read(connectionProvider.notifier).reapply();
                      },
                    ),
                  ],
                ),
              ),
            // Bulk action bar for the ticked zones.
            if (_selected.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 2, bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.auroraTeal.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.auroraTeal.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'Выбрано: ${_selected.length}',
                      style: AppType.ui(
                        12.5,
                        weight: FontWeight.w700,
                        color: AppColors.auroraTeal,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(_selected.clear),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.mist,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Снять'),
                    ),
                    TextButton.icon(
                      onPressed: () => _showBulkEditTarget(context, ref, nodes),
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: Text(
                        'Задать вариант',
                        style: AppType.ui(12.5, weight: FontWeight.w700),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.auroraTeal,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          // One-tap profile tuned for Russia (local resources direct, blocked
          // services through the tunnel).
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.auroraTeal,
                side: const BorderSide(color: AppColors.hairlineStrong),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(
                'Готовый профиль для России',
                style: AppType.ui(13, weight: FontWeight.w700),
              ),
              onPressed: () => _applyRussiaPreset(context, ref),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.signalRed,
                side: const BorderSide(color: AppColors.hairlineStrong),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.block_rounded, size: 18),
              label: Text(
                'Заблокировать рекламные зоны',
                style: AppType.ui(13, weight: FontWeight.w700),
              ),
              onPressed: () => _applyAdsPreset(context, ref),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _presets)
                if (!rules.containsKey(p))
                  ActionChip(
                    backgroundColor: AppColors.abyss,
                    side: const BorderSide(color: AppColors.hairline),
                    label: Text('+ .$p', style: AppType.mono(12)),
                    onPressed: () => _showAdd(context, ref, nodes, preset: p),
                  ),
              ActionChip(
                backgroundColor: AppColors.abyss,
                side: const BorderSide(color: AppColors.hairline),
                avatar: const Icon(
                  Icons.add_rounded,
                  color: AppColors.auroraTeal,
                  size: 16,
                ),
                label: Text('Своя зона', style: AppType.ui(12)),
                onPressed: () => _showAdd(context, ref, nodes),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Changes where an existing zone is routed, keeping the zone itself.
  Future<void> _showEditTarget(
    BuildContext context,
    WidgetRef ref,
    String zone,
    String current,
    List<ProxyNode> nodes,
  ) async {
    var target = current;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.slate,
          title: Text(
            '.$zone',
            style: AppType.mono(17, weight: FontWeight.w700),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Куда направить',
                  style: AppType.ui(12, color: AppColors.mist),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in _targets.entries)
                          _choice(
                            label: entry.value.$1,
                            color: entry.value.$2,
                            selected: target == entry.key,
                            onTap: () => setState(() => target = entry.key),
                          ),
                        for (final n in nodes)
                          _choice(
                            label: CountryFlags.cleanName(n.name),
                            color: AppColors.auroraTeal,
                            selected: target == n.id,
                            onTap: () => setState(() => target = n.id),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && target != current) {
      ref.read(settingsProvider.notifier).setDomainZoneRule(zone, target);
      ref.read(connectionProvider.notifier).reapply();
    }
  }

  Widget _tick(bool on) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        gradient: on ? AppColors.auroraGradient : null,
        color: on ? null : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: on ? Colors.transparent : AppColors.hairlineStrong,
        ),
      ),
      child: on
          ? const Icon(Icons.check_rounded, size: 15, color: AppColors.voidBg)
          : null,
    );
  }

  /// Applies one target to every ticked zone at once, then clears the selection.
  Future<void> _showBulkEditTarget(
    BuildContext context,
    WidgetRef ref,
    List<ProxyNode> nodes,
  ) async {
    final zones = _selected.toList();
    String? target;
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: AppColors.slate,
          title: Text('Для ${zones.length} зон', style: AppType.display(17)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Куда направить выбранные зоны',
                  style: AppType.ui(12, color: AppColors.mist),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in _targets.entries)
                          _choice(
                            label: entry.value.$1,
                            color: entry.value.$2,
                            selected: target == entry.key,
                            onTap: () => setLocal(() => target = entry.key),
                          ),
                        for (final n in nodes)
                          _choice(
                            label: CountryFlags.cleanName(n.name),
                            color: AppColors.auroraTeal,
                            selected: target == n.id,
                            onTap: () => setLocal(() => target = n.id),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: target == null
                  ? null
                  : () => Navigator.pop(context, target),
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    ref.read(settingsProvider.notifier).addDomainZoneRules({
      for (final z in zones) z: chosen,
    });
    ref.read(connectionProvider.notifier).reapply();
    setState(_selected.clear);
  }

  Future<void> _applyAdsPreset(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.slate,
        title: Text('Рекламные зоны', style: AppType.display(18)),
        content: Text(
          'Добавит ${_adsPreset.length} зон рекламных и трекинговых сетей '
          '(Google Ads, AdMob, Criteo, AppsFlyer, AdRiver и другие) со '
          'значением «Блок».\n\n'
          'Это дополняет переключатель «Блокировка рекламы» в настройках '
          'туннеля: там список из ~187 тысяч доменов, а эти зоны видны в '
          'списке — любую можно переключить обратно, если она что-то ломает.',
          style: AppType.ui(13, color: AppColors.mist),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Применить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(settingsProvider.notifier).addDomainZoneRules(_adsPreset);
    ref.read(connectionProvider.notifier).reapply();
    messenger.showSnackBar(
      SnackBar(content: Text('Добавлено зон: ${_adsPreset.length}')),
    );
  }

  Future<void> _applyRussiaPreset(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.slate,
        title: Text('Профиль для России', style: AppType.display(18)),
        content: Text(
          'Добавит ${_russiaPreset.length} правил: российские сайты и сервисы '
          '(.ru, .рф, VK, Яндекс, банки, 2ГИС) пойдут напрямую, а YouTube, '
          'Instagram, Discord, ChatGPT и другие заблокированные — через VPN.\n\n'
          'Ваши уже добавленные зоны сохранятся; совпадающие будут обновлены.',
          style: AppType.ui(13, color: AppColors.mist),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Применить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(settingsProvider.notifier).addDomainZoneRules(_russiaPreset);
    ref.read(connectionProvider.notifier).reapply();
    messenger.showSnackBar(
      SnackBar(content: Text('Добавлено правил: ${_russiaPreset.length}')),
    );
  }

  /// (label, colour) for a zone target: one of the fixed modes, or a server
  /// name when the target is a node id.
  (String, Color) _targetInfo(String target, List<ProxyNode> nodes) {
    final fixed = _targets[target];
    if (fixed != null) return fixed;
    for (final n in nodes) {
      if (n.id == target) {
        return (CountryFlags.cleanName(n.name), AppColors.frost);
      }
    }
    return ('сервер удалён', AppColors.mistDim);
  }

  Widget _targetChip(String target, List<ProxyNode> nodes) {
    final (label, color) = _targetInfo(target, nodes);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.ui(11.5, weight: FontWeight.w700, color: color),
      ),
    );
  }

  Future<void> _showAdd(
    BuildContext context,
    WidgetRef ref,
    List<ProxyNode> nodes, {
    String? preset,
  }) async {
    final controller = TextEditingController(text: preset ?? '');
    var target = 'direct';
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.slate,
          title: Text('Доменная зона', style: AppType.display(18)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: preset == null,
                  style: AppType.ui(14),
                  decoration: const InputDecoration(
                    hintText: 'например: ru, рф, google.com',
                    prefixText: '.',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Куда направить',
                  style: AppType.ui(12, color: AppColors.mist),
                ),
                const SizedBox(height: 8),
                // Bounded height so the chip list scrolls cleanly inside the
                // dialog instead of an unbounded Flexible (which rendered broken).
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in _targets.entries)
                          _choice(
                            label: entry.value.$1,
                            color: entry.value.$2,
                            selected: target == entry.key,
                            onTap: () => setState(() => target = entry.key),
                          ),
                        // One chip per server — routes this zone through it.
                        for (final n in nodes)
                          _choice(
                            label: CountryFlags.cleanName(n.name),
                            color: AppColors.auroraTeal,
                            selected: target == n.id,
                            onTap: () => setState(() => target = n.id),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      final zone = controller.text.trim();
      if (zone.isNotEmpty) {
        ref.read(settingsProvider.notifier).setDomainZoneRule(zone, target);
        // Apply immediately if connected, so the new rule takes effect without
        // a manual reconnect.
        ref.read(connectionProvider.notifier).reapply();
      }
    }
  }

  Widget _choice({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      selected: selected,
      selectedColor: color.withValues(alpha: 0.25),
      backgroundColor: AppColors.abyss,
      labelStyle: AppType.ui(
        12.5,
        weight: FontWeight.w700,
        color: selected ? color : AppColors.mist,
      ),
      onSelected: (_) => onTap(),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, color: AppColors.auroraTeal, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: AppType.ui(14.5, weight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.mist),
          ],
        ),
      ),
    );
  }
}

class _RoutingCard extends StatelessWidget {
  const _RoutingCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });
  final RoutingMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      highlight: selected,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: selected ? AppColors.auroraTeal : AppColors.mistDim,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode.title,
                  style: AppType.ui(14.5, weight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  mode.subtitle,
                  style: AppType.ui(12, color: AppColors.mist),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.mist, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.ui(14.5, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: AppType.ui(12, color: AppColors.mist)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _StackTile extends StatelessWidget {
  const _StackTile({required this.stack, required this.onPick});
  final TunStack stack;
  final ValueChanged<TunStack> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.layers_rounded, color: AppColors.mist, size: 22),
          const SizedBox(width: 14),
          Text(
            'Сетевой стек',
            style: AppType.ui(14.5, weight: FontWeight.w600),
          ),
          const Spacer(),
          PopupMenuButton<TunStack>(
            color: AppColors.slate,
            initialValue: stack,
            onSelected: onPick,
            itemBuilder: (_) => [
              for (final st in TunStack.values)
                PopupMenuItem(value: st, child: Text(st.label)),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.voidBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stack.label,
                    style: AppType.mono(
                      12,
                      weight: FontWeight.w700,
                      color: AppColors.auroraTeal,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: AppColors.mist,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditTile extends StatelessWidget {
  const _EditTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onSave,
  });

  final IconData icon;
  final String title;
  final String value;
  final ValueChanged<String> onSave;

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: AppType.display(18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppType.ui(14),
          decoration: const InputDecoration(hintText: 'https://…/dns-query'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) onSave(result);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _edit(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.mist, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppType.ui(14.5, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: AppType.mono(11.5, color: AppColors.mist),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_rounded, color: AppColors.mistDim, size: 17),
          ],
        ),
      ),
    );
  }
}
