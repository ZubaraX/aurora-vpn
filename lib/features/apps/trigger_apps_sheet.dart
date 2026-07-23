import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/installed_app.dart';
import '../../state/connection_controller.dart';
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

class _TriggerAppsSheetState extends ConsumerState<TriggerAppsSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(settingsProvider).triggerApps;
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
                      const Icon(Icons.rocket_launch_rounded,
                          color: AppColors.auroraTeal, size: 20),
                      const SizedBox(width: 10),
                      Text('Триггер-приложения', style: AppType.display(19)),
                      const Spacer(),
                      if (selected.isNotEmpty)
                        TextButton(
                          onPressed: ctrl.clearTriggerApps,
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.mist),
                          child: const Text('Очистить'),
                        ),
                    ],
                  ),
                  Text(
                    'VPN подключится автоматически, когда откроется любое из выбранных приложений.',
                    style: AppType.ui(12.5, color: AppColors.mist),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: AppType.ui(14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Поиск приложения',
                      hintStyle: AppType.ui(14, color: AppColors.mistDim),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.mist, size: 20),
                      filled: true,
                      fillColor: AppColors.voidBg,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.hairline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: AppColors.auroraTeal, width: 1.3),
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
                  var list = apps.where((a) => !a.isSystem).toList();
                  if (_query.isNotEmpty) {
                    final q = _query.toLowerCase();
                    list = list.where((a) => a.name.toLowerCase().contains(q)).toList();
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _row(
                      list[i],
                      selected.contains(list[i].id),
                      () => ctrl.toggleTriggerApp(list[i].id),
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

  Widget _row(InstalledApp app, bool checked, VoidCallback onTap) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      highlight: checked,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.slateHi,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.apps_rounded, size: 20, color: AppColors.mist),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(app.name,
                style: AppType.ui(14, weight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: checked ? AppColors.auroraGradient : null,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                  color: checked ? Colors.transparent : AppColors.hairlineStrong),
            ),
            child: checked
                ? const Icon(Icons.check_rounded, size: 17, color: AppColors.voidBg)
                : null,
          ),
        ],
      ),
    );
  }
}
