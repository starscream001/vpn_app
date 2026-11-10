# Native VPN 0.2.0 — экспериментальная интеграция

## Реализовано в коде

- iOS 15+: PacketTunnel Xcode target, App Group, entitlements, SingBoxTunnel pod, настоящий NEPacketTunnelProvider через GPL sing_box/libbox. Приложение управляет native start/stop/status/stats напрямую, без высокоуровневого сохранения профилей сторонним Dart SDK.
- Windows/Linux/macOS: отдельный официальный sing-box 1.14.4 с TUN (IPv4/IPv6, DNS hijacking), конфигурация передаётся stdin, не пишется в файл и не попадает в аргументы процесса. Core поставляется рядом с executable; URL и SHA-256 закреплены. Не используется системный HTTP proxy вместо TUN.
- VLESS TCP Reality/TLS, ручные доменные исключения и ru/рф/su, HTTPS-проверка и native counters. На desktop проба принудительно идёт через отдельный HTTP inbound, даже если домен добавлен в исключения. Clash API только loopback, случайный секрет на каждый запуск.
- Android по-прежнему использует исходные AWG/Xray адаптеры.

## Что требуется для запуска

**iOS:** платный Apple Developer аккаунт, bundle IDs app.foxway.foxway и app.foxway.foxway.PacketTunnel, App Group group.app.foxway.foxway, provisioning и Network Extension entitlement у обоих targets. Unsigned build проверяет компиляцию, не устанавливается на iPhone. Настоящее подключение требует физического устройства и тестового endpoint.

**Desktop:** создание TUN и изменение маршрутов требуют OS privileges. Текущий process adapter сам не повышает права и не устанавливает сервис. Без прав он завершится с ошибкой, а UI не покажет «Подключено». На Linux можно отдельно предоставить cap_net_admin доверенному core; на Windows требуется административный запуск; на macOS требуется привилегированный backend. Полноценные установщики signed privileged helpers/XPC/Windows service ещё не реализованы. GUI не следует распространять как законченный потребительский desktop VPN без этого этапа. macOS build предназначен для прямой загрузки, App Sandbox выключен в конфигурации приложения; App Store вариант потребует отдельного Network Extension.

Принудительное завершение GUI может оставить дочерний core работающим: надёжный supervisor и восстановление native состояния остаются обязательными задачами helper/service. Исключения приложений вне Android отклоняются явно.

## Оставшиеся протоколы

AmneziaWG 2.0 на iOS/desktop **не реализован**. Vanilla sing-box WireGuard не является AWG. Native adapter явно отклоняет AWG; Авто может выбрать доступный VLESS. Следующий отдельный шаг — официальный amneziawg-apple/WireGuardKitGo и AWG backend для desktop с проверкой полей S/H/I.

## Проверки

Локально: 33 Flutter tests проходят, формат и analyzer проверяются; официальный sing-box 1.14.4 успешно выполнил `check` для desktop и iOS JSON fixtures. Команда check не запускает VPN и не меняет маршруты компьютера. Полные native сборки выполняются в GitHub Actions. Действующие VPN-серверы не трогаются.

До релиза нужны: tests реального TUN на отдельном стенде, DNS/IPv6, рассыпание сети, reconnect/revoke, права и native supervisor, Apple signing/device validation, аудит iOS shared container protection и GPL corresponding sources. Старый релиз 0.1.0 не заменяется непроверенными сборками.
