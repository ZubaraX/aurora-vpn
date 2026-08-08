import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/connection_controller.dart';
import '../../state/profile_controller.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../apps/apps_screen.dart';
import '../apps/trigger_app_monitor.dart';
import '../home/home_screen.dart';
import '../servers/servers_screen.dart';
import '../settings/settings_screen.dart';
import '../update/update_dialog.dart';
import 'aurora_background.dart';

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell>
    with WidgetsBindingObserver {
  static const _screens = [
    HomeScreen(),
    ServersScreen(),
    AppsScreen(),
    SettingsScreen(),
  ];

  static const _dests = [
    (
      icon: Icons.shield_outlined,
      active: Icons.shield_rounded,
      label: 'Главная',
    ),
    (icon: Icons.dns_outlined, active: Icons.dns_rounded, label: 'Серверы'),
    (
      icon: Icons.apps_outlined,
      active: Icons.apps_rounded,
      label: 'Приложения',
    ),
    (icon: Icons.tune_outlined, active: Icons.tune_rounded, label: 'Настройки'),
  ];

  Timer? _triggerTimer;
  final _triggerMonitor = TriggerAppMonitor();
  bool _checkingTriggers = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoConnect();
      _checkTriggerApps();
      _checkForUpdate();
    });
    _triggerTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkTriggerApps(),
    );
  }

  Future<void> _checkForUpdate() async {
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    final info = await ref.read(updateServiceProvider).check();
    if (!mounted || info == null) return;
    showUpdateDialog(context, info);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _triggerTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref
        .read(profileProvider.notifier)
        .refreshIfStale(maxAge: const Duration(minutes: 2));
    _checkTriggerApps();
  }

  void _maybeAutoConnect() {
    final settings = ref.read(settingsProvider);
    if (!settings.autoConnect) return;
    if (ref.read(connectionProvider).status.isActive) return;
    ref.read(connectionProvider.notifier).connect();
  }

  /// Auto-connects when a trigger app newly appears in the running set (and we
  /// aren't already connected). Edge detection avoids reconnecting right after a
  /// manual disconnect while the trigger app keeps running.
  Future<void> _checkTriggerApps() async {
    if (_checkingTriggers) return;
    _checkingTriggers = true;
    try {
      final settings = ref.read(settingsProvider);
      final triggers = settings.triggerApps;
      if (triggers.isEmpty) {
        _triggerMonitor.reset();
        return;
      }
      final inventory = ref.read(appInventoryProvider);
      final results = await Future.wait([
        inventory.runningIds(),
        inventory.activeNetworkType(),
      ]);
      if (!mounted) return;
      final running = results[0] as Set<String>;
      final networkType = results[1] as String;
      final connection = ref.read(connectionProvider);
      final action = _triggerMonitor.evaluate(
        settings: settings,
        runningIds: running,
        networkType: networkType,
        connectionStatus: connection.status,
        activeNodeId: settings.activeNodeId,
      );
      if (action != null) {
        final notifier = ref.read(connectionProvider.notifier);
        if (action.disconnect) {
          // "No VPN" is configured for this app on this network.
          await notifier.disconnect();
        } else {
          await notifier.connectToIds(action.profileIds);
        }
      }
    } finally {
      _checkingTriggers = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(navIndexProvider);
    final wide = MediaQuery.sizeOf(context).width >= 760;

    final content = IndexedStack(index: index, children: _screens);

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: wide ? _wide(content, index) : content,
        bottomNavigationBar: wide ? null : _bottomBar(index),
      ),
    );
  }

  Widget _wide(Widget content, int index) {
    return Row(
      children: [
        _SideRail(
          index: index,
          onSelect: (i) => ref.read(navIndexProvider.notifier).state = i,
        ),
        const VerticalDivider(
          width: 1,
          thickness: 1,
          color: AppColors.hairline,
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _bottomBar(int index) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.abyss,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.transparent,
          indicatorColor: AppColors.auroraTeal.withValues(alpha: 0.16),
          labelTextStyle: WidgetStateProperty.all(
            AppType.ui(11, weight: FontWeight.w600),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(
              color: s.contains(WidgetState.selected)
                  ? AppColors.auroraTeal
                  : AppColors.mist,
            ),
          ),
        ),
        child: NavigationBar(
          height: 66,
          selectedIndex: index,
          onDestinationSelected: (i) =>
              ref.read(navIndexProvider.notifier).state = i,
          destinations: [
            for (final d in _dests)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.active),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 214,
      color: AppColors.abyss.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 32),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: AppColors.auroraGradient,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    size: 18,
                    color: AppColors.voidBg,
                  ),
                ),
                const SizedBox(width: 10),
                ShaderMask(
                  shaderCallback: (r) =>
                      AppColors.auroraGradient.createShader(r),
                  child: Text(
                    'Aurora',
                    style: AppType.display(
                      20,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < _RootShellState._dests.length; i++)
            _railItem(i, _RootShellState._dests[i], i == index),
          const Spacer(),
          Text(
            'sing-box core',
            style: AppType.mono(10, color: AppColors.mistDim),
          ),
        ],
      ),
    );
  }

  Widget _railItem(
    int i,
    ({IconData icon, IconData active, String label}) d,
    bool on,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: on ? AppColors.slate : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: () => onSelect(i),
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  on ? d.active : d.icon,
                  size: 20,
                  color: on ? AppColors.auroraTeal : AppColors.mist,
                ),
                const SizedBox(width: 12),
                Text(
                  d.label,
                  style: AppType.ui(
                    13.5,
                    weight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on ? AppColors.frost : AppColors.mist,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
