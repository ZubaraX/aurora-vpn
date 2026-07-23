# Aurora

**Универсальный прокси-клиент на базе sing-box** — как Happ, только чище и аккуратнее.
Один код на **Windows** и **Android**: подписки, красивый интерфейс и раздельное
туннелирование по приложениям (per-app routing / split tunneling).

> Собрано на Flutter. Windows-версия собирается и запускается **без каких-либо
> дополнительных настроек** (нет нативных плагинов, шрифты встроены, хранилище
> файловое). Уже проверено: `flutter analyze` чист, юнит-тесты проходят, `.exe`
> собирается и запускается.

---

## Что умеет

- **Подписки.** Вставьте ссылку `https://…` или сразу строки узлов. Поддержаны
  форматы: `vless://` (+ Reality/uTLS), `vmess://`, `trojan://`, `ss://`,
  `hysteria2://` / `hy2://`, `tuic://`, а также **base64-обёрнутые** списки узлов.
  Читается заголовок `Subscription-Userinfo` — трафик и срок действия показываются
  прогресс-баром.
- **Автогенерация конфига sing-box.** Каждый узел превращается в корректный
  `outbound`, а из настроек собирается полный конфиг: TUN-inbound, split-DNS,
  правила маршрутизации, geosite/geoip rule-sets, блок рекламы.
- **Per-app routing (split tunneling).**
  - Android — `include_package` / `exclude_package` на TUN-inbound.
  - Windows — правила маршрута по `process_name` (реальные процессы берутся из
    `tasklist`).
  - Режимы: «только выбранные» (allowlist) и «кроме выбранных» (blocklist).
- **Замер пинга.** Реальный TCP-хэндшейк до каждого узла, сортировка по задержке,
  авто-выбор самого быстрого.
- **Живые метрики.** Скорость загрузки/отдачи, длительность сессии, объём трафика.
- **Маршрутизация:** умные правила / всё через VPN / прямое подключение.
- **Красивый UI:** тёмная тема «полярное сияние», фирменный **Aurora Orb**
  (дышащее кольцо-кнопка подключения), адаптив — боковая панель на Windows,
  нижняя навигация на телефоне.

---

## Как запустить

### Windows (готово из коробки)

```bash
flutter pub get
flutter run -d windows          # запуск
flutter build windows           # release-сборка → build/windows/x64/runner/Release/aurora.exe
```

Приложение работает сразу. Ядро подключается так:

1. Скачайте `sing-box.exe` с https://github.com/SagerNet/sing-box/releases
2. Положите его рядом с `aurora.exe` (или в подпапку `core/`, или в `PATH`).
3. Запустите Aurora **от администратора** (поднятие TUN-интерфейса требует прав).

Если ядро не найдено — приложение работает в режиме **DEMO** (симуляция статуса
и трафика), чтобы можно было полностью изучить интерфейс. Индикатор `CORE` / `DEMO`
виден в шапке и в разделе «Настройки».

### Android

Нужны Android SDK cmdline-tools и принятые лицензии:

```bash
flutter doctor --android-licenses
flutter build apk               # или flutter run -d <device>
```

Нативная часть уже написана (`android/app/src/main/kotlin/com/auroravpn/aurora/`):
`MainActivity.kt` (каналы + запрос согласия на VPN + список приложений) и
`AuroraVpnService.kt` (VpnService, foreground-уведомление, поток статуса/трафика).
Чтобы туннель заработал по-настоящему, добавьте AAR ядра sing-box (`libbox`) в
`android/app/libs` и запустите `BoxService` в помеченном месте
`AuroraVpnService.kt` — вся обвязка вокруг уже готова.

---

## Архитектура

```
lib/
├─ core/theme/            палитра, типографика (встроенные шрифты), тема
├─ core/utils/            форматирование (байты, скорость, время)
├─ data/
│  ├─ models/             ProxyNode, Subscription, VpnSettings, InstalledApp, …
│  ├─ parsers/            разбор подписок и share-ссылок всех протоколов
│  └─ local/              файловое хранилище + пути (без плагинов)
├─ engine/
│  ├─ singbox_config.dart генератор полного конфига sing-box
│  ├─ vpn_engine.dart     общий интерфейс движка
│  ├─ windows_engine.dart реальный запуск sing-box.exe + Clash API статистика
│  ├─ android_engine.dart мост к VpnService через MethodChannel
│  ├─ simulated_engine.dart реалистичная симуляция (DEMO)
│  ├─ latency_service.dart TCP-пинг
│  └─ app_inventory.dart  список приложений (Android/Windows/образец)
├─ state/                 Riverpod: settings / profile / connection
├─ features/              экраны: home, servers, apps, settings, shell
└─ widgets/               общие компоненты (стекло-карты, бейджи, кнопки)
```

**Поток данных:** экран → контроллер (Riverpod) → движок (`VpnEngine`).
`SingBoxConfigBuilder` — единственное место, где рождается конфиг ядра; выше него
код одинаков для обеих платформ, различается лишь способ применения per-app правил.

---

## Стек

- **Flutter** (Dart) — общий UI и логика
- **flutter_riverpod** — состояние
- **http** — загрузка подписок
- **sing-box** — прокси-ядро (внешний бинарник на Windows, `libbox` на Android)
- Встроенные шрифты: **Space Grotesk**, **Manrope**, **JetBrains Mono**

## Проверка

```bash
flutter analyze     # без замечаний
flutter test        # парсер подписок и генератор конфига покрыты тестами
```

---

*DEMO-режим не туннелирует реальный трафик — он существует, чтобы показать
интерфейс без сервера. Подставьте `sing-box.exe` (Windows) или `libbox` (Android)
и свои узлы из подписки — и туннель станет боевым.*
