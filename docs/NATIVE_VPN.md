# Native VPN 0.3

Для session kill switch см. [PROTECTION](PROTECTION.md); для self-update — [UPDATES](UPDATES.md). Ниже — движки и границы native интеграции.

# Native VPN 0.2.0 — экспериментальная интеграция

| Платформа | VLESS TCP Reality/TLS | AmneziaWG 2.0 | Исключения |
|---|---|---|---|
| Android | Xray | AWG Android 2.3.7 | Приложения: оба движка; домены: VLESS |
| iOS 15+ | sing-box/libbox PacketTunnel | Отдельный AWGPacketTunnel, официальный Go bridge | Домены: VLESS; выбор приложений не реализован |
| Windows x64 | sing-box TUN | Официальный AWG service через собственный controller | Домены: VLESS |
| Linux x64 | sing-box TUN | AWG Go + ограниченный awg-quick | Домены: VLESS |
| macOS | sing-box TUN process | Отдельный AWG Network Extension | Домены: VLESS |

Это матрица реализации, а не подтверждение реальных VPN-подключений. Без отдельного тестового сервера проверяем компиляцию, логику и локальные fixtures. Настоящие TUN, DNS/IPv6 и переподключение на устройствах ещё не проверены.

## Передача конфигурации

- Desktop VLESS: официальный sing-box 1.14.4, URL и SHA-256 закреплены; конфигурация через stdin, без ключей в командной строке или файлах. Loopback Clash API защищён случайным секретом. HTTPS-проба принудительно идёт через отдельный proxy inbound.
- Apple VLESS и AWG: отдельный процесс расширения исключает конфликт двух Go runtimes. Конфигурация в общем Keychain, в NE preferences только account ID; расширение возвращает только счётчики. Предыдущая default Keychain access group сохранена первой для обновлений vault.
- Windows AWG: собственный короткоживущий helper вызывает официальный upstream service. Профиль зашифрован Windows DPAPI machine scope в каталоге Program Files с доступом SYSTEM/Administrators. Сервис создаётся с demand start, имя привязано к пользователю, executable размещается в защищённом каталоге версии. Hooks из импортированных конфигов запрещены. Полный GUI в этом preview запрашивает административные права; разделение прав через подписанный broker остаётся следующим этапом.
- Linux AWG: только stdin и собственное имя интерфейса `fw` + hash UID; raw-конфиги на диск не записываются. Hooks и SaveConfig запрещены. Используется системный диалог pkexec для awg-quick; требуются iproute2, resolvconf, iptables или nftables, polkit/pkexec и /dev/net/tun. Бинарники AWG поставляются в bundle. Не запускайте несколько VPN одновременно: upstream route/DNS scripts не обеспечивают изоляцию произвольных сторонних VPN.

## Права и подпись

**iOS:** unsigned Runner.app содержит два расширения, но не устанавливается на iPhone. Для проверки нужны Apple Team, provisioning, capabilities и физическое устройство. [Инструкция](IOS.md).

**Windows:** запуск GUI вызывает UAC; установка драйвера/сервиса в CI не выполняется. Подпись publisher и установщик отсутствуют.

**Linux:** VLESS core требует NET_ADMIN/NET_RAW либо административного запуска. Для AWG предусмотрен pkexec. AppImage/DEB и установка capabilities пока не реализованы.

**macOS:** AWG extension требует разрешённой Apple подписи и provisioning. Ad-hoc упаковка не даёт Network Extension права и не проходит Gatekeeper/notarization. Для VLESS process нужны повышенные права; App Sandbox host выключен, поэтому этот вариант не предназначен для Mac App Store. Подписанный helper/XPC и VLESS NE на macOS ещё не реализованы.

## Границы проверки

Обычное закрытие окна вызывает stop, но после аварийного завершения GUI tunnel/service может остаться работающим. Надёжный supervisor/reconciliation, автоматическое восстановление после сна после reboot остаются отдельными задачами; session guard добавлен в 0.3, но не проверен на настоящих устройствах. AWG проверяется по HTTPS и росту counters: это не доказательство прохождения конкретного HTTPS-запроса через AWG при произвольных AllowedIPs. Домены .ru/.рф/.su — эвристика российских сайтов, не геобаза. Для AWG доменных исключений нет; ручные домены явно отклоняются.

Плагин sing_box vendored только для iOS: неиспользуемая Android-регистрация конфликтовала по gomobile go.Seq с Xray. Подробности и corresponding sources: [лицензии](LICENSES.md), [исходники](SOURCES.md).
