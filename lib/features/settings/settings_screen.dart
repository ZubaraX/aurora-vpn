import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/enums.dart';
import '../../state/connection_controller.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/ui_bits.dart';
import '../logs/logs_screen.dart';
import '../update/update_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final conn = ref.read(connectionProvider.notifier);

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
                  onTap: () => ctrl.setRoutingMode(m),
                ),
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
                      onChanged: ctrl.setTunMode,
                    ),
                    _tileDivider(),
                    _StackTile(stack: s.tunStack, onPick: ctrl.setTunStack),
                    _tileDivider(),
                    _SwitchTile(
                      icon: Icons.lan_rounded,
                      title: 'Обход локальной сети',
                      subtitle: 'Приватные адреса идут напрямую',
                      value: s.bypassLan,
                      onChanged: ctrl.setBypassLan,
                    ),
                    _tileDivider(),
                    _SwitchTile(
                      icon: Icons.block_rounded,
                      title: 'Блокировка рекламы',
                      subtitle: 'Правило geosite-ads → reject',
                      value: s.blockAds,
                      onChanged: ctrl.setBlockAds,
                    ),
                    _tileDivider(),
                    _SwitchTile(
                      icon: Icons.public_rounded,
                      title: 'IPv6',
                      subtitle: 'Двойной стек в туннеле',
                      value: s.ipv6,
                      onChanged: ctrl.setIpv6,
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
                      onSave: ctrl.setDnsRemote,
                    ),
                    _tileDivider(),
                    _EditTile(
                      icon: Icons.router_rounded,
                      title: 'DNS напрямую',
                      value: s.dnsDirect,
                      onSave: ctrl.setDnsDirect,
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
