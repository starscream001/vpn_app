# FoxWay 0.3.1 — проверенные результаты

Дата: 10 ноября 2026. Проверенный source commit: `07b053b4389ee26780369d7c88109d6d981ee5f7`.
[GitHub Actions 42897599045](https://github.com/starscream001/vpn_app/actions/runs/42897599045): **success**, все семь jobs и загрузка артефактов успешны. Приложение и build workflow в коммите публикации не изменяются; release job проверяет это автоматически.

## Результаты

| Проверка | Результат |
|---|---|
| Dart format / Flutter analyze | PASS, без замечаний |
| Flutter tests | **59 PASS** |
| Python API/firewall/updater tests | **16 PASS** |
| Официальный sing-box 1.14.4 `check` | PASS, iOS и desktop fixtures |
| Native loopback routing | PASS для обеих fixtures: .ru direct; другие домены и forced quality probes не переходят в direct при отказе proxy |
| Android | Debug APK, universal release APK, 3 ABI APK, AAB — PASS |
| iOS | AWG Go bridge, VLESS/AWG Packet Tunnel extensions, unsigned Runner.app — PASS |
| Windows | Flutter release, Go AWG/controller/persistent WFP helper, updater PowerShell syntax, Wintun/core packaging — PASS |
| Linux | Flutter release, AWG Go + C tools, nft helper и updater packaging — PASS |
| macOS | AWG bridge arm64/x86_64, native extension, оба sing-box executable, ditto archive — PASS |
| Corresponding sources | PASS, около 1.13 GB, source/dependency/license archive |

## Артефакты точного source commit

- [Android APK/AAB](https://github.com/starscream001/vpn_app/actions/runs/42897599045/artifacts/13801238186)
- [iOS unsigned](https://github.com/starscream001/vpn_app/actions/runs/42897599045/artifacts/13800733419)
- [Windows](https://github.com/starscream001/vpn_app/actions/runs/42897599045/artifacts/13800024985)
- [Linux](https://github.com/starscream001/vpn_app/actions/runs/42897599045/artifacts/13802155605)
- [macOS](https://github.com/starscream001/vpn_app/actions/runs/42897599045/artifacts/13802011739)
- [Corresponding sources](https://github.com/starscream001/vpn_app/actions/runs/42897599045/artifacts/13800853600)
- [Coverage и UI captures](https://github.com/starscream001/vpn_app/actions/runs/42897599045/artifacts/13800937861)

Постоянные public assets и SHA256SUMS: [Releases](https://github.com/starscream001/vpn_app/releases). Actions artifacts имеют срок хранения. Предыдущий [0.2 preview](https://github.com/starscream001/vpn_app/releases/tag/v0.2.0-preview.1) сохранён.

## Исправления 0.3.1

- Вставка HTTPS-ссылки загружает и сохраняет подписку, показывает число серверов и expiry при наличии заголовка. Повторный импорт не дублирует источник; сбой обновления сохраняет старые серверы.
- Ограниченные HTTPS-перенаправления, base64 с переносами и BOM, понятные ошибки без секретных URL/ответов, блокировка повторной отправки, корректное закрытие окна импорта.
- Отмена подключения во время native start и проверки, игнорирование позднего результата, повторная остановка поздно запущенного туннеля. На Android остановка обоих движков и отмена ожидающего разрешения AWG. Это проверено моделированием задержек и сборкой Android, без физического устройства.
- Новые проверки: 6 тестов импорта/сохранения, 2 теста отмены в контроллере, 3 сценария интерфейса. Всего 59 Flutter и 16 Python тестов.

[Механика импорта](SUBSCRIPTIONS.md).

## Что проверяют тесты

- Semver/prerelease precedence; отказ чужим update URLs, HTTP и опасным asset names; выбор platform assets.
- Смешанная подписка существующего бота, пропуск несовместимых профилей, expiry raw AWG и VLESS, сохранение источников в vault.
- Strict policy временно убирает direct domains/app exclusions, сохраняя исходные предпочтения.
- Ошибка bind, failed quality и обычный stop не снимают persistent desktop guard; явный disconnect снимает.
- Перед обновлением остановка core сериализована с записью vault и не освобождает активный guard.
- Apple fake platform получает On Demand/includeAllNetworks без optional LAN/APNs bypass; quality inbound остаётся proxy-only.
- PF layout с ранним quick pass/конкурирующим anchor отвергается; стандартный Apple entry point поддержан.
- nft render покрывает обе IP families и не содержит established bypass/глобального flush ruleset; interface injection запрещён.
- Updater archive validation отклоняет hash mismatch, traversal/absolute paths, нормализованные aliases, symlinks, неполный bundle. Linux capabilities сохраняются только при достаточных правах; неподходящие права приводят к отказу до замены.
- Интерфейс 390×844, landscape и desktop; 200% текст; scrollable confirmation защиты и отмена без изменения настроек. Скриншоты главной и вкладки подписки просмотрены визуально.

## Локальные проверки

49 Flutter и 16 Python tests PASS, analyzer без замечаний. Windows AWG/WFP helper cross-build Windows/amd64 PASS без выполнения Windows API. Linux AWG CLI cross-build и C tools compilation PASS. Две native JSON fixtures успешно проверены официальным macOS sing-box; оба routing smoke использовали только loopback, без TUN. Package validator использовал временные zip fixtures, не установленное приложение.

Полного Xcode локально нет; Apple compilation подтверждена GitHub runners. Нативная сборка Windows/Linux Flutter выполнялась на соответствующих runners. Полные логи/steps доступны по ссылке CI выше.

## Telegram: точный статус

Подключён клиентский путь к **@Ilyavpnadmin_bot** через уже выдаваемые постоянные ссылки `sub.ilyamanik.ru`. Добавлены открытие бота, импорт plain/base64 feed, обновление каждые 15 минут во время работы приложения, обработка срока из header и сохранение working cache. Это не новый бот и не новый poller. Код/служба действующего бота, базы и VPN endpoints не менялись; реальные сообщения от имени бота не отправлялись.

Новый v1 bearer API/quality collector **не развёрнут и не привязан к боевому боту**. По URL-подписке отчёты автоматически не уходят. Вход по коду появляется только при настроенном API. [Механика выдачи/продления/отзыва](MECHANICS.md), [контракт API](API.md).

## Подпись и обновление: точный статус

Автопроверка новой версии, проверенная загрузка и platform handoff реализованы. Windows/Linux updater готовит bundle до закрытия приложения, сохраняет предыдущую папку и выполняет rollback при части ошибок rename/start. На настоящей установленной программе автоматическая замена не выполнялась: это требует отдельного теста прав, locks, crash/power-loss и запуска GUI.

Android installer сверяет package/version/signing certificates. Этот CI run использовал **тестовую подпись**. Постоянный keystore создан локально, но автоматически сохранить его в repository secrets не удалось; секреты не считаются настроенными. Дальнейшие надёжные Android updates требуют одного постоянного ключа; старые тестовые APK могут иметь другой signer. Клиент откажет, а не удалит vault. Private keys не входят в Git, release assets или CI cache.

macOS пока открывает проверенный archive, не заменяет подписанный NE app unsigned сборкой. iOS использует будущий App Store/TestFlight URL, который ещё не задан. Apple account/Team/provisioning отсутствуют по согласованию с пользователем. [Подробно об обновлениях и откате](UPDATES.md).

## Ограничения защиты

**Реальные VPN-подключения, применение WFP/nft/PF, сброс соединений PF, Android lockdown и гибель core/GUI на устройствах не тестировались.** Пользователь не предоставил отдельный VPN test endpoint. Успешная compilation и fake tests не доказывают отсутствие DNS/IPv6 leaks.

Session protection реализована, но не заявляется полным boot-time always-on firewall. Android lockdown включается/отключается пользователем в ОС. Apple сохраняет обязательные системные исключения. macOS PF требует root и совместимого layout, очищает connection states при активации. Удаление guard не является доказательством остановки orphan VLESS core после crash: полноценный supervisor/reconciliation ещё нужен. [Аварийное восстановление и все границы](PROTECTION.md).

Перед production: изолированные устройства/сервер, оба IP families/DNS, существующие TCP/UDP при arm, crash core/GUI, failover, sleep/reboot, отказ прав, корректное снятие guard, чужой firewall, установка/откат новой версии, стабильная подпись, Apple entitlements, signing/binary SBOM/16 KB review.

Действующие VPN-серверы, их конфигурации, данные клиентов и текущие VPN-подключения компьютера не изменялись.
