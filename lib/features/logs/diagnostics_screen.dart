import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/country_flags.dart';
import '../../data/models/enums.dart';
import '../../state/connection_controller.dart';
import '../../state/profile_controller.dart';
import '../../state/settings_controller.dart';
import '../../widgets/glass_card.dart';

/// Outcome of a single diagnostic step.
enum _Verdict { pass, fail, warn }

class _Check {
  const _Check(this.title, this.verdict, this.detail);
  final String title;
  final _Verdict verdict;
  final String detail;
}

/// Answers "why isn't it working?" without reading raw core logs.
///
/// Each step isolates one link in the chain — tunnel up, traffic through the
/// tunnel, plain internet, name resolution — so a failure points at the actual
/// cause (dead server vs. blocked DNS vs. no connectivity at all) instead of
/// leaving the user to guess.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  final _results = <_Check>[];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _results.clear();
    });

    void add(_Check c) {
      if (mounted) setState(() => _results.add(c));
    }

    final conn = ref.read(connectionProvider);
    final settings = ref.read(settingsProvider);
    final node = ref.read(profileProvider).nodeById(settings.activeNodeId);

    // 1. Is a server selected at all?
    add(node == null
        ? const _Check('Сервер выбран', _Verdict.fail,
            'Сервер не выбран — откройте вкладку «Серверы».')
        : _Check('Сервер выбран', _Verdict.pass,
            '${CountryFlags.cleanName(node.name)} · ${node.server}:${node.port}'));

    // 2. Is the server reachable at all (plain TCP, outside the tunnel)?
    if (node != null) {
      final reachable = await _tcpOk(node.server, node.port);
      add(_Check(
        'Сервер отвечает',
        reachable ? _Verdict.pass : _Verdict.fail,
        reachable
            ? 'TCP-соединение установлено.'
            : 'Сервер не отвечает на ${node.server}:${node.port}. '
                'Он может быть выключен или заблокирован вашей сетью — '
                'смените сервер.',
      ));
    }

    // 3. Is the tunnel actually up?
    final connected = conn.status == ConnectionStatus.connected;
    add(_Check(
      'Туннель подключён',
      connected ? _Verdict.pass : _Verdict.warn,
      connected ? 'VPN активен.' : 'VPN не подключён — проверки ниже без него.',
    ));

    // 4. Does traffic actually pass through the tunnel?
    if (connected) {
      final ok = await ref.read(connectionProvider.notifier).probeTunnel();
      add(_Check(
        'Трафик идёт через VPN',
        ok ? _Verdict.pass : _Verdict.fail,
        ok
            ? 'Проверочный запрос прошёл через туннель.'
            : 'Туннель поднят, но трафик не проходит. Обычно это мёртвый '
                'сервер — выберите другой.',
      ));
    }

    // 5. Plain internet, so "nothing works" can be told from "VPN broken".
    final direct = await _httpOk('https://ya.ru');
    add(_Check(
      'Интернет доступен',
      direct ? _Verdict.pass : _Verdict.fail,
      direct ? 'Прямой запрос прошёл.' : 'Нет доступа даже напрямую — '
          'проблема в сети устройства, а не в VPN.',
    ));

    // 6. Censored destination: separates DNS poisoning from a dead server.
    final censored = await _httpOk('https://www.youtube.com');
    add(_Check(
      'Заблокированный сайт открывается',
      censored ? _Verdict.pass : _Verdict.warn,
      censored
          ? 'YouTube отвечает.'
          : 'YouTube не отвечает. Если туннель работает, проверьте доменные '
              'зоны: возможно, он направлен на отдельный неработающий сервер.',
    ));

    if (mounted) setState(() => _running = false);
  }

  Future<bool> _tcpOk(String host, int port) async {
    try {
      final s = await Socket.connect(host, port,
          timeout: const Duration(seconds: 6));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _httpOk(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      await resp.drain<void>();
      return resp.statusCode > 0;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.voidBg,
      appBar: AppBar(
        backgroundColor: AppColors.voidBg,
        title: Text('Диагностика', style: AppType.display(19)),
        actions: [
          IconButton(
            tooltip: 'Повторить',
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            'Проверяем цепочку по шагам, чтобы стало видно, где именно обрыв.',
            style: AppType.ui(12.5, color: AppColors.mist),
          ),
          const SizedBox(height: 14),
          for (final c in _results)
            GlassCard(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_icon(c.verdict), color: _color(c.verdict), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.title,
                            style: AppType.ui(14, weight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(c.detail,
                            style: AppType.ui(12, color: AppColors.mist)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_running)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  IconData _icon(_Verdict v) => switch (v) {
        _Verdict.pass => Icons.check_circle_rounded,
        _Verdict.fail => Icons.cancel_rounded,
        _Verdict.warn => Icons.info_rounded,
      };

  Color _color(_Verdict v) => switch (v) {
        _Verdict.pass => AppColors.signalGreen,
        _Verdict.fail => AppColors.signalRed,
        _Verdict.warn => AppColors.signalAmber,
      };
}
