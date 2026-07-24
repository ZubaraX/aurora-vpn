import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/country_flags.dart';
import '../../data/models/installed_app.dart';
import '../../data/models/proxy_node.dart';
import '../../state/connection_controller.dart';
import '../../state/profile_controller.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../../widgets/glass_card.dart';

/// Picker for "trigger apps": launching any of them auto-connects the tunnel.
class TriggerAppsSheet extends ConsumerStatefulWidget {
  const TriggerAppsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const TriggerAppsSheet(),
  );

  @override
  ConsumerState<TriggerAppsSheet> createState() => _TriggerAppsSheetState();
}

class _TriggerAppsSheetState extends ConsumerState<TriggerAppsSheet>
    with WidgetsBindingObserver {
  String _query = '';
  bool? _hasTriggerAccess;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTriggerAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshTriggerAccess();
  }

  Future<void> _refreshTriggerAccess() async {
    final allowed = await ref.read(appInventoryProvider).hasTriggerAccess();
    if (mounted) setState(() => _hasTriggerAccess = allowed);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final selected = settings.triggerApps;
    final ctrl = ref.read(settingsProvider.notifier);
    final appsAsync = ref.watch(installedAppsProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.slateHi,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.rocket_launch_rounded,
                        color: AppColors.auroraTeal,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text('Триггер-приложения', style: AppType.display(19)),
                      const Spacer(),
                      if (selected.isNotEmpty)
                        TextButton(
                          onPressed: ctrl.clearTriggerApps,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.mist,
                          ),
                          child: const Text('Очистить'),
                        ),
                    ],
                  ),
                  Text(
                    'При открытии приложения VPN подключится или переключится на выбранный для текущей сети сервер.',
                    style: AppType.ui(12.5, color: AppColors.mist),
                  ),
                  if (_hasTriggerAccess == false) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                      decoration: BoxDecoration(
                        color: AppColors.slate,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.visibility_outlined,
                            size: 18,
                            color: AppColors.auroraTeal,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Разрешите доступ к статистике использования для определения запуска приложений.',
                              style: AppType.ui(11.5, color: AppColors.mist),
                            ),
                          ),
                          TextButton(
                            onPressed: () => ref
                                .read(appInventoryProvider)
                                .requestTriggerAccess(),
                            child: const Text('Разрешить'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: AppType.ui(14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Поиск приложения',
                      hintStyle: AppType.ui(14, color: AppColors.mistDim),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.mist,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: AppColors.voidBg,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.hairline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.auroraTeal,
                          width: 1.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: appsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const SizedBox.shrink(),
                data: (apps) {
                  final nodes = ref.watch(profileProvider).nodes;
                  final known = apps.map((a) => a.id).toSet();
                  var list = [
                    ...apps.where((a) => !a.isSystemService),
                    for (final id in selected.keys)
                      if (!known.contains(id))
                        InstalledApp(id: id, name: _pretty(id)),
                  ];
                  if (_query.isNotEmpty) {
                    final q = _query.toLowerCase();
                    list = list
                        .where((a) => a.name.toLowerCase().contains(q))
                        .toList();
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _row(
                      list[i],
                      selected.containsKey(list[i].id),
                      settings.triggerProfileFor(list[i].id, 'wifi'),
                      settings.triggerProfileFor(list[i].id, 'mobile'),
                      nodes,
                      ctrl,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    InstalledApp app,
    bool checked,
    String wifiProfileId,
    String mobileProfileId,
    List<ProxyNode> nodes,
    SettingsController ctrl,
  ) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      highlight: checked,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.slateHi,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.apps_rounded,
                  size: 20,
                  color: AppColors.mist,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  app.name,
                  style: AppType.ui(14, weight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => ctrl.toggleTriggerApp(app.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    gradient: checked ? AppColors.auroraGradient : null,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: checked
                          ? Colors.transparent
                          : AppColors.hairlineStrong,
                    ),
                  ),
                  child: checked
                      ? const Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: AppColors.voidBg,
                        )
                      : null,
                ),
              ),
            ],
          ),
          if (checked) ...[
            const SizedBox(height: 10),
            _profileRow(
              icon: Icons.wifi_rounded,
              title: 'Wi-Fi',
              profileId: wifiProfileId,
              nodes: nodes,
              onSelected: (value) => ctrl.setTriggerWifiProfile(app.id, value),
            ),
            const SizedBox(height: 8),
            _profileRow(
              icon: Icons.signal_cellular_alt_rounded,
              title: 'Мобильная сеть',
              profileId: mobileProfileId,
              nodes: nodes,
              onSelected: (value) =>
                  ctrl.setTriggerMobileProfile(app.id, value),
            ),
          ],
        ],
      ),
    );
  }

  Widget _profileRow({
    required IconData icon,
    required String title,
    required String profileId,
    required List<ProxyNode> nodes,
    required ValueChanged<String> onSelected,
  }) {
    ProxyNode? profileNode;
    for (final node in nodes) {
      if (node.id == profileId) {
        profileNode = node;
        break;
      }
    }
    final label = profileId.isEmpty
        ? 'Текущий сервер'
        : (profileNode == null
              ? 'узел удалён'
              : CountryFlags.cleanName(profileNode.name));

    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.mistDim),
        const SizedBox(width: 8),
        Text(title, style: AppType.ui(12, color: AppColors.mist)),
        const Spacer(),
        PopupMenuButton<String>(
          color: AppColors.slate,
          onSelected: onSelected,
          itemBuilder: (_) => [
            const PopupMenuItem(value: '', child: Text('Текущий сервер')),
            for (final node in nodes)
              PopupMenuItem(
                value: node.id,
                child: Text(
                  CountryFlags.cleanName(node.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.voidBg,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 132),
                  child: Text(
                    label,
                    style: AppType.ui(
                      12.5,
                      weight: FontWeight.w700,
                      color: AppColors.auroraTeal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
    );
  }

  /// `chrome.exe` → `chrome`; a package id is left as-is.
  String _pretty(String id) =>
      id.replaceAll(RegExp(r'\.exe$', caseSensitive: false), '');
}
