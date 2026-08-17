import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/enums.dart';
import '../../state/connection_controller.dart';
import '../../state/profile_controller.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../apps/apps_screen.dart';
import '../apps/trigger_app_monitor.dart';
import '../home/home_screen.dart';
import '../servers/servers_screen.dart';
import '../settings/settings_screen.dart';
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
  Timer? _updateTimer;
  final _triggerMonitor = TriggerAppMonitor();
  bool _checkingTriggers = false;
  bool _checkingUpdate = false;
  DateTime _lastTriggerSwitch = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastUpdateCheck = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoConnect();
      _checkTriggerApps();
      _checkForUpdate(delay: const Duration(seconds: 4));
    });
    _triggerTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkTriggerApps(),
    );
    _updateTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _checkForUpdate(),
    );
  }

  /// Looks for a newer release, and keeps looking until it finds one.
  ///
  /// A single attempt at launch reached almost nobody: GitHub is typically
  /// unreachable on a restricted network until the tunnel is up, and four
  /// seconds in it rarely is — so the one attempt failed silently and no banner
  /// or notification ever appeared. Now the check also runs when the tunnel
  /// comes up, when the app is resumed, and every 30 minutes.
  Future<void> _checkForUpdate({Duration delay = Duration.zero}) async {
    if (_checkingUpdate) return;
    // Already found — the banner stays until the user updates.
    if (ref.read(updateAvailableProvider) != null) return;
    final now = DateTime.now();
    if (now.difference(_lastUpdateCheck) < const Duration(minutes: 2)) return;
    _lastUpdateCheck = now;
    _checkingUpdate = true;
    try {
      if (delay > Duration.zero) await Future.delayed(delay);
      if (!mounted) return;
      final info = await ref.read(updateServiceProvider).check();
      if (!mounted || info == null) return;
      // Surface it as a persistent banner on the home screen (see _UpdateBanner)
      // instead of an intrusive dialog on every launch.
      ref.read(updateAvailableProvider.notifier).state = info;
      // Also push a shade notification — once per version, so it isn't repeated
      // on every launch while the same update stays pending.
      final storage = ref.read(storageProvider);
      if (storage.readMap('aurora.update')?['notified'] != info.version) {
        await ref.read(updateServiceProvider).notifyAvailable(info.version);
        await storage.writeJson('aurora.update', {'notified': info.version});
      }
    } finally {
      _checkingUpdate = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _triggerTimer?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref
        .read(profileProvider.notifier)
        .refreshIfStale(maxAge: const Duration(minutes: 2));
    _checkTriggerApps();
    _checkForUpdate();
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
    // Cool-down after a trigger-initiated switch. Flipping quickly between two
    // trigger apps that use different servers (YouTube ↔ Telegram) otherwise
    // restarts the core on every switch, so the tunnel never settles and the
    // connection appears to drop. Skipping the evaluation entirely (rather than
    // discarding the action) keeps the monitor's state intact, so the correct
    // profile is still applied once things calm down.
    if (DateTime.now().difference(_lastTriggerSwitch) <
        const Duration(seconds: 20)) {
      return;
    }
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
        _lastTriggerSwitch = DateTime.now();
        final notifier = ref.read(connectionProvider.notifier);
        final settingsCtrl = ref.read(settingsProvider.notifier);
        if (action.disconnect) {
          // "Без VPN" for this app on this network: send just this app around
          // the tunnel and keep the VPN up for everything else. Killing the
          // whole tunnel meant the user had to turn it back on by hand.
          //
          // Reload only when the bypass set really changed: a trigger app that
          // stays in the foreground is re-evaluated every cool-down window, and
          // reloading each time restarted the core under live traffic.
          if (settingsCtrl.setBypassPackage(action.appId, true)) {
            await notifier.reapply();
          }
        } else {
          // Leaving a no-VPN app: stop bypassing it again.
          final unbypassed = settingsCtrl.setBypassPackage(action.appId, false);
          final before = ref.read(settingsProvider).activeNodeId;
          await notifier.connectToIds(action.profileIds);
          // connectToIds is a no-op when the pool is already connected, so the
          // dropped bypass would never reach the core — reload it ourselves.
          if (unbypassed &&
              ref.read(settingsProvider).activeNodeId == before &&
              ref.read(connectionProvider).status.isActive) {
            await notifier.reapply();
          }
        }
      }
    } finally {
      _checkingTriggers = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // On a restricted network GitHub is typically only reachable through the
    // tunnel, so a fresh connection is the moment a check can finally succeed.
    ref.listen(connectionProvider.select((s) => s.status), (_, status) {
      if (status == ConnectionStatus.connected) {
        _checkForUpdate(delay: const Duration(seconds: 3));
      }
    });
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
