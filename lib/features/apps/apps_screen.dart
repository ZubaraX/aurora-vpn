import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/enums.dart';
import '../../data/models/installed_app.dart';
import '../../state/connection_controller.dart';
import '../../state/settings_controller.dart';
import '../../widgets/glass_card.dart';
import 'trigger_apps_sheet.dart';

enum _AppFilter { all, selected }

class AppsScreen extends ConsumerStatefulWidget {
  const AppsScreen({super.key});

  @override
  ConsumerState<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends ConsumerState<AppsScreen> {
  String _query = '';
  _AppFilter _filter = _AppFilter.all;
  bool _hideSystem = true;

  List<InstalledApp> _filtered(List<InstalledApp> apps, Set<String> selected) {
    var list = apps;
    if (_hideSystem) list = list.where((a) => !a.isSystemService).toList();
    if (_filter == _AppFilter.selected) {
      list = list.where((a) => selected.contains(a.id)).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((a) => a.name.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final appsAsync = ref.watch(installedAppsProvider);
    final enabled = settings.perAppMode != PerAppMode.off;
    final selected = settings.perAppSelected;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                child: Row(
                  children: [
                    Text('По приложениям', style: AppType.display(24)),
                    const Spacer(),
                    if (selected.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.auroraTeal.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${selected.length} выбрано',
                          style: AppType.ui(
                            12,
                            weight: FontWeight.w700,
                            color: AppColors.auroraTeal,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Обновить список',
                      onPressed: () => ref.invalidate(installedAppsProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      color: AppColors.mist,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: appsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text(
                      'Не удалось получить список приложений',
                      style: AppType.ui(13, color: AppColors.signalRed),
                    ),
                  ),
                  data: (apps) {
                    // Always show selected apps even if they aren't currently
                    // running / in the scanned list, so a selection never looks
                    // lost after reopening the app.
                    final knownIds = apps.map((a) => a.id).toSet();
                    final merged = [
                      ...apps,
                      for (final id in selected)
                        if (!knownIds.contains(id))
                          InstalledApp(id: id, name: _pretty(id)),
                    ];
                    final list = _filtered(merged, selected);
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                      children: [
                        Text(
                          Platform.isAndroid
                              ? 'Выберите, какие приложения используют VPN. Остальные идут напрямую.'
                              : 'Раздельное туннелирование по процессам. Выбор сопоставляется с правилами sing-box по имени процесса.',
                          style: AppType.ui(13, color: AppColors.mist),
                        ),
                        const SizedBox(height: 16),
                        GlassCard(
                          onTap: () => TriggerAppsSheet.show(context),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.rocket_launch_rounded,
                                color: AppColors.auroraTeal,
                                size: 20,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Автоподключение при запуске',
                                      style: AppType.ui(
                                        14,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'VPN включится сам, когда откроется выбранное приложение',
                                      style: AppType.ui(
                                        12,
                                        color: AppColors.mist,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (settings.triggerApps.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.auroraTeal.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${settings.triggerApps.length}',
                                    style: AppType.ui(
                                      12,
                                      weight: FontWeight.w700,
                                      color: AppColors.auroraTeal,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.mist,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _modeSelector(settings.perAppMode, ctrl.setPerAppMode),
                        const SizedBox(height: 18),
                        _controls(enabled, list, selected, ctrl),
                        const SizedBox(height: 12),
                        if (list.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Text(
                              _filter == _AppFilter.selected
                                  ? 'Пока ничего не выбрано'
                                  : 'Ничего не найдено',
                              textAlign: TextAlign.center,
                              style: AppType.ui(14, color: AppColors.mist),
                            ),
                          )
                        else
                          Opacity(
                            opacity: enabled ? 1 : 0.5,
                            child: Column(
                              children: [
                                for (final app in list)
                                  _AppRow(
                                    app: app,
                                    checked: selected.contains(app.id),
                                    enabled: enabled,
                                    onTap: () => ctrl.toggleApp(app.id),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Controls (search + filter + bulk actions) ---------------------------

  Widget _controls(
    bool enabled,
    List<InstalledApp> list,
    Set<String> selected,
    SettingsController ctrl,
  ) {
    final allChecked =
        list.isNotEmpty && list.every((a) => selected.contains(a.id));
    return Column(
      children: [
        _search(enabled),
        const SizedBox(height: 12),
        Row(
          children: [
            _filterChip(
              'Все',
              _filter == _AppFilter.all,
              () => setState(() => _filter = _AppFilter.all),
            ),
            const SizedBox(width: 8),
            _filterChip(
              'Выбранные',
              _filter == _AppFilter.selected,
              () => setState(() => _filter = _AppFilter.selected),
            ),
            const Spacer(),
            _action(
              allChecked ? Icons.remove_done_rounded : Icons.done_all_rounded,
              allChecked ? 'Снять' : 'Все',
              enabled && list.isNotEmpty
                  ? () => allChecked
                        ? ctrl.deselectApps(list.map((a) => a.id))
                        : ctrl.selectApps(list.map((a) => a.id))
                  : null,
            ),
            const SizedBox(width: 4),
            _action(
              Icons.clear_rounded,
              'Очистить',
              enabled && selected.isNotEmpty ? ctrl.clearApps : null,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.settings_suggest_rounded,
              size: 15,
              color: AppColors.mistDim,
            ),
            const SizedBox(width: 8),
            Text(
              'Скрывать системные службы',
              style: AppType.ui(12.5, color: AppColors.mist),
            ),
            const Spacer(),
            Switch(
              value: _hideSystem,
              onChanged: (v) => setState(() => _hideSystem = v),
            ),
          ],
        ),
      ],
    );
  }

  Widget _filterChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.auroraTeal.withValues(alpha: 0.16)
              : AppColors.abyss,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: active ? AppColors.auroraTeal : AppColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: AppType.ui(
            12.5,
            weight: FontWeight.w700,
            color: active ? AppColors.auroraTeal : AppColors.mist,
          ),
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) {
    final on = onTap != null;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: AppType.ui(12.5, weight: FontWeight.w700)),
      style: TextButton.styleFrom(
        foregroundColor: on ? AppColors.frost : AppColors.mistDim,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _search(bool enabled) {
    return TextField(
      enabled: enabled,
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
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.hairline.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  // --- Mode selector -------------------------------------------------------

  Widget _modeSelector(PerAppMode mode, void Function(PerAppMode) onPick) {
    return Column(
      children: [
        Row(
          children: [
            for (final m in PerAppMode.values)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: m == PerAppMode.values.last ? 0 : 8,
                  ),
                  child: _modePill(m, m == mode, () => onPick(m)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          mode.subtitle,
          style: AppType.ui(12.5, color: AppColors.mist),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _modePill(PerAppMode m, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: active ? AppColors.auroraGradient : null,
          color: active ? null : AppColors.abyss,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? Colors.transparent : AppColors.hairline,
          ),
        ),
        child: Text(
          _short(m),
          style: AppType.ui(
            12.5,
            weight: FontWeight.w800,
            color: active ? AppColors.voidBg : AppColors.mist,
          ),
        ),
      ),
    );
  }

  String _short(PerAppMode m) => switch (m) {
    PerAppMode.off => 'Весь трафик',
    PerAppMode.allowlist => 'Только выбранные',
    PerAppMode.blocklist => 'Кроме выбранных',
  };

  /// `chrome.exe` → `chrome`; a package id is left as-is.
  String _pretty(String id) =>
      id.replaceAll(RegExp(r'\.exe$', caseSensitive: false), '');
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.checked,
    required this.enabled,
    required this.onTap,
  });

  final InstalledApp app;
  final bool checked;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      highlight: checked,
      onTap: enabled ? onTap : null,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.slateHi,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              app.isSystemService
                  ? Icons.settings_suggest_rounded
                  : Icons.apps_rounded,
              size: 20,
              color: AppColors.mist,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.name,
                  style: AppType.ui(14, weight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  app.id,
                  style: AppType.mono(10.5, color: AppColors.mistDim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _check(checked),
        ],
      ),
    );
  }

  Widget _check(bool on) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        gradient: on ? AppColors.auroraGradient : null,
        color: on ? null : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: on ? Colors.transparent : AppColors.hairlineStrong,
        ),
      ),
      child: on
          ? const Icon(Icons.check_rounded, size: 17, color: AppColors.voidBg)
          : null,
    );
  }
}
