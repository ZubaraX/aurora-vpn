import 'package:flutter/material.dart';

/// Proxy protocols Aurora can parse and hand to the sing-box core.
enum ProxyProtocol {
  vless('VLESS'),
  vmess('VMess'),
  trojan('Trojan'),
  shadowsocks('Shadowsocks'),
  hysteria2('Hysteria2'),
  tuic('TUIC'),
  wireguard('WireGuard'),
  socks('SOCKS'),
  http('HTTP');

  const ProxyProtocol(this.label);
  final String label;

  /// Short badge shown on server cards.
  String get badge => switch (this) {
        ProxyProtocol.vless => 'VLESS',
        ProxyProtocol.vmess => 'VMESS',
        ProxyProtocol.trojan => 'TROJAN',
        ProxyProtocol.shadowsocks => 'SS',
        ProxyProtocol.hysteria2 => 'HY2',
        ProxyProtocol.tuic => 'TUIC',
        ProxyProtocol.wireguard => 'WG',
        ProxyProtocol.socks => 'SOCKS',
        ProxyProtocol.http => 'HTTP',
      };
}

/// The lifecycle of the tunnel, driven by [ConnectionController].
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error;

  bool get isActive => this == connected || this == connecting;
}

/// How traffic is routed once connected.
enum RoutingMode {
  rule('Умная маршрутизация', 'Правила: обход локальных и заблокированных ресурсов'),
  global('Глобально через VPN', 'Весь трафик идёт в туннель'),
  direct('Прямое подключение', 'Туннель поднят, но трафик идёт напрямую');

  const RoutingMode(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

/// Per-app split-tunneling mode.
enum PerAppMode {
  off('Выключено', 'Все приложения используют выбранный режим'),
  allowlist('Только выбранные', 'Через VPN идут только отмеченные приложения'),
  blocklist('Кроме выбранных', 'Отмеченные приложения идут напрямую');

  const PerAppMode(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

/// sing-box TUN network stack.
enum TunStack {
  mixed('Mixed'),
  system('System'),
  gvisor('gVisor');

  const TunStack(this.label);
  final String label;
}

extension ConnectionStatusUi on ConnectionStatus {
  String get title => switch (this) {
        ConnectionStatus.disconnected => 'Не подключено',
        ConnectionStatus.connecting => 'Подключение…',
        ConnectionStatus.connected => 'Защищено',
        ConnectionStatus.disconnecting => 'Отключение…',
        ConnectionStatus.error => 'Ошибка',
      };

  IconData get icon => switch (this) {
        ConnectionStatus.disconnected => Icons.shield_outlined,
        ConnectionStatus.connecting => Icons.sync_rounded,
        ConnectionStatus.connected => Icons.verified_user_rounded,
        ConnectionStatus.disconnecting => Icons.sync_rounded,
        ConnectionStatus.error => Icons.error_outline_rounded,
      };
}
