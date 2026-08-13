import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/country_flags.dart';
import '../../data/models/installed_app.dart';
import '../../data/models/proxy_node.dart';
import '../../data/models/vpn_settings.dart';
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
                    'При открытии приложения Aurora переключится на сервер, '
                    'выбранный для текущей сети. Wi-Fi и мобильная сеть '
                    'настраиваются отдельно — для любой из них можно выбрать '
                    '«Без VPN».',
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
                      settings.triggerProfilesFor(list[i].id, 'mobile'),
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
    List<String> mobileProfileIds,
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
            _mobileProfileRow(
              icon: Icons.signal_cellular_alt_rounded,
              title: 'Мобильная сеть',
              profileIds: mobileProfileIds,
              nodes: nodes,
              onTap: () => _showMobileProfiles(
                app: app,
                selectedIds: mobileProfileIds,
                nodes: nodes,
                ctrl: ctrl,
              ),
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
    final label = profileId == kTriggerNoVpn
        ? 'Без VPN'
        : profileId.isEmpty
            ? 'Текущий сервер'
            // The id is kept: the server may simply be absent from the latest
            // subscription refresh and come back on the next one.
            : (profileNode == null
                  ? 'сервер недоступен'
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
            const PopupMenuItem(value: kTriggerNoVpn, child: Text('Без VPN')),
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

  Widget _mobileProfileRow({
    required IconData icon,
    required String title,
    required List<String> profileIds,
    required List<ProxyNode> nodes,
    required VoidCallback onTap,
  }) {
    final noVpn = profileIds.length == 1 && profileIds.first == kTriggerNoVpn;
    final byId = {for (final node in nodes) node.id: node};
    final selected = profileIds
        .map((id) => byId[id])
        .whereType<ProxyNode>()
        .toList();
    // Count every saved id, not just the ones that resolve right now: a server
    // missing from the latest subscription refresh is temporarily unavailable,
    // not removed, and the pool still holds it.
    final total = profileIds.where((id) => id.isNotEmpty).length;
    final missing = total - selected.length;
    final label = noVpn
        ? 'Без VPN'
        : switch (total) {
            0 => 'Текущий сервер',
            1 => selected.isEmpty
                ? 'сервер недоступен'
                : CountryFlags.cleanName(selected.first.name),
            _ => missing > 0
                ? '$total серверов · $missing недоступно'
                : '$total серверов · автоподбор',
          };

    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.mistDim),
        const SizedBox(width: 8),
        Text(title, style: AppType.ui(12, color: AppColors.mist)),
        const Spacer(),
        GestureDetector(
          onTap: onTap,
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
                  constraints: const BoxConstraints(maxWidth: 170),
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
                const SizedBox(width: 3),
                const Icon(
                  Icons.playlist_add_check_rounded,
                  color: AppColors.mist,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showMobileProfiles({
    required InstalledApp app,
    required List<String> selectedIds,
    required List<ProxyNode> nodes,
    required SettingsController ctrl,
  }) async {
    // Keep ids that do not currently resolve to a node. A subscription refresh
    // can temporarily omit a server (or return it under a changed config), and
    // dropping those ids here would PERMANENTLY delete them from the pool the
    // moment the user pressed save — the "галочки удаляются сами" complaint.
    // They stay selected, invisible in the list, and are written back intact.
    final selected = <String>{
      for (final id in selectedIds)
        if (id.isNotEmpty) id,
    };
    var query = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = query.isEmpty
              ? nodes
              : nodes
                    .where(
                      (node) => CountryFlags.cleanName(
                        node.name,
                      ).toLowerCase().contains(query.toLowerCase()),
                    )
                    .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.86,
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
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Мобильная сеть · ${app.name}',
                                style: AppType.display(18),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${selected.length}/20',
                              style: AppType.mono(
                                12,
                                color: selected.length == 20
                                    ? AppColors.auroraTeal
                                    : AppColors.mist,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Серверы проверяются по порядку. Aurora выберет первый, который реально передаёт данные.',
                          style: AppType.ui(12, color: AppColors.mist),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          onChanged: (value) =>
                              setSheetState(() => query = value),
                          style: AppType.ui(14),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Поиск сервера',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final node = filtered[index];
                        final checked = selected.contains(node.id);
                        final order = selected.toList().indexOf(node.id) + 1;
                        return CheckboxListTile(
                          value: checked,
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          activeColor: AppColors.auroraTeal,
                          title: Text(
                            CountryFlags.cleanName(node.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            node.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          secondary: checked
                              ? CircleAvatar(
                                  radius: 13,
                                  backgroundColor: AppColors.auroraTeal
                                      .withValues(alpha: 0.16),
                                  child: Text(
                                    '$order',
                                    style: AppType.mono(
                                      11,
                                      color: AppColors.auroraTeal,
                                    ),
                                  ),
                                )
                              : null,
                          onChanged: (value) {
                            if (value == true &&
                                !checked &&
                                selected.length >= 20) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Можно выбрать не более 20 серверов',
                                  ),
                                ),
                              );
                              return;
                            }
                            setSheetState(() {
                              value == true
                                  ? selected.add(node.id)
                                  : selected.remove(node.id);
                            });
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => setSheetState(selected.clear),
                          child: const Text('Текущий'),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.mist,
                          ),
                          onPressed: () {
                            ctrl.setTriggerMobileProfiles(
                                app.id, const [kTriggerNoVpn]);
                            Navigator.pop(sheetContext);
                          },
                          child: const Text('Без VPN'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: () {
                            ctrl.setTriggerMobileProfiles(app.id, selected);
                            Navigator.pop(sheetContext);
                          },
                          icon: const Icon(Icons.check_rounded),
                          label: Text('Сохранить · ${selected.length}'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// `chrome.exe` → `chrome`; a package id is left as-is.
  String _pretty(String id) =>
      id.replaceAll(RegExp(r'\.exe$', caseSensitive: false), '');
}
