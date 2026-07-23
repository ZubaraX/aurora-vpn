import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/update/update_service.dart';
import '../../state/providers.dart';

/// Shows the "update available" dialog and drives the download/apply flow.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends ConsumerStatefulWidget {
  const _UpdateDialog({required this.info});
  final UpdateInfo info;

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  double? _progress;
  bool _busy = false;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    final ok = await ref.read(updateServiceProvider).apply(
          widget.info,
          onProgress: (p) => mounted ? setState(() => _progress = p) : null,
        );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = Platform.isAndroid
            ? 'Скачивание запущено. Установите APK вручную, если система не предложила.'
            : 'Обновление недоступно для этой платформы.';
      });
    }
    // On Windows the app exits into the updater; nothing else to do here.
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: AppColors.auroraGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.system_update_rounded,
                color: AppColors.voidBg, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('Обновление ${info.version}', style: AppType.display(18))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info.notes.trim().isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Text(info.notes.trim(),
                    style: AppType.ui(13, color: AppColors.mist)),
              ),
            )
          else
            Text('Доступна новая версия Aurora.',
                style: AppType.ui(13, color: AppColors.mist)),
          if (_busy) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_progress ?? 0) > 0 ? _progress : null,
                minHeight: 6,
                backgroundColor: AppColors.slateHi,
                valueColor: const AlwaysStoppedAnimation(AppColors.auroraTeal),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _progress != null && _progress! > 0
                  ? 'Загрузка ${((_progress ?? 0) * 100).round()}%'
                  : 'Загрузка…',
              style: AppType.mono(11, color: AppColors.mist),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: AppType.ui(12.5, color: AppColors.signalAmber)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.mist),
          child: const Text('Позже'),
        ),
        TextButton(
          onPressed: _busy ? null : _update,
          style: TextButton.styleFrom(foregroundColor: AppColors.auroraTeal),
          child: Text(Platform.isWindows ? 'Обновить и перезапустить' : 'Обновить'),
        ),
      ],
    );
  }
}
