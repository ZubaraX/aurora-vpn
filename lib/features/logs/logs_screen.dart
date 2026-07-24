import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/connection_controller.dart';

/// Shows the core logs and any recorded crash/error, so failures can be
/// diagnosed on-device without adb. Android reads its native log files via a
/// platform channel; other platforms read the engine's captured output.
class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  static const _channel = MethodChannel('aurora/logs');

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  String _text = 'Загрузка…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String text;
    if (Platform.isAndroid) {
      try {
        text = await LogsScreen._channel.invokeMethod<String>('read') ?? '';
      } catch (e) {
        text = 'Не удалось прочитать логи: $e';
      }
    } else {
      final conn = ref.read(connectionProvider.notifier);
      final err = conn.lastError;
      text = [
        if (err != null) '═══ Последняя ошибка ═══\n$err',
        '═══ Ядро (${conn.backendLabel}) ═══\n${conn.diagnostics}',
      ].join('\n\n');
    }
    if (mounted) setState(() => _text = text.trim().isEmpty ? 'Логи пусты.' : text);
  }

  Future<void> _clear() async {
    if (Platform.isAndroid) {
      try {
        await LogsScreen._channel.invokeMethod('clear');
      } catch (_) {}
    }
    _load();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Скопировано в буфер')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.voidBg,
      appBar: AppBar(
        backgroundColor: AppColors.abyss,
        surfaceTintColor: Colors.transparent,
        title: Text('Логи', style: AppType.display(19)),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.frost),
          ),
          IconButton(
            tooltip: 'Копировать',
            onPressed: _copy,
            icon: const Icon(Icons.copy_rounded, color: AppColors.frost),
          ),
          IconButton(
            tooltip: 'Очистить',
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.mist),
          ),
        ],
      ),
      body: SafeArea(
        child: Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              _text,
              style: AppType.mono(11.5, color: AppColors.frost),
            ),
          ),
        ),
      ),
    );
  }
}
