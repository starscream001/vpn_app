# Проверки FoxWay 0.2.0 — 10 ноября 2026

Проверенный source commit: `5bf8b7871fd7fee2a0851e138011f1c52cc3320a`.
[GitHub Actions run 42764187193](https://github.com/starscream001/vpn_app/actions/runs/42764187193): **success**, все 7 jobs успешны, все 7 артефактов загружены. Документация и workflow публикации добавлены следующим коммитом; приложение и build workflow после проверенного SHA не менялись.

| Проверка | Результат |
|---|---|
| Dart format / Flutter analyze | PASS, без замечаний |
| Flutter unit/widget tests | 36 PASS |
| Backend tests | 5 PASS |
| Официальный sing-box 1.14.4 `check` | PASS для iOS и desktop JSON |
| Native loopback routing smoke | PASS для обеих конфигураций: .ru direct; другой домен и принудительная quality-проба не переходят в direct при отказе прокси |
| Android | Debug APK, universal release APK, 3 ABI APK, AAB — PASS |
| iOS | AWG Go bridge + два Packet Tunnel расширения + unsigned Runner.app — PASS |
| Windows x64 | Flutter release, AWG service/controller Go build, Wintun и sing-box packaging — PASS |
| Linux x64 | Flutter release, AWG Go CLI + C tools и sing-box packaging — PASS |
| macOS | AWG Go bridge arm64/x86_64, Flutter release с AWG extension, sing-box для обеих архитектур — PASS |
| Corresponding sources | PASS, архив приложения/ядер/Go-зависимостей/Dart-плагинов, около 1.13 GB |

## Артефакты проверенного прогона

- [Android APK/AAB](https://github.com/starscream001/vpn_app/actions/runs/42764187193/artifacts/13739178396)
- [iOS unsigned](https://github.com/starscream001/vpn_app/actions/runs/42764187193/artifacts/13738623532)
- [Windows x64](https://github.com/starscream001/vpn_app/actions/runs/42764187193/artifacts/13739182367)
- [Linux x64](https://github.com/starscream001/vpn_app/actions/runs/42764187193/artifacts/13739187080)
- [macOS](https://github.com/starscream001/vpn_app/actions/runs/42764187193/artifacts/13738518794)
- [Corresponding sources](https://github.com/starscream001/vpn_app/actions/runs/42764187193/artifacts/13739660441)
- [Coverage и снимок UI](https://github.com/starscream001/vpn_app/actions/runs/42764187193/artifacts/13739201900)

Actions-артефакты имеют ограниченный срок хранения. Публичные файлы и SHA256SUMS публикуются отдельно в [Releases](https://github.com/starscream001/vpn_app/releases). Apple bundles заранее упакованы через ditto на Apple runner: транспорт артефактов не уничтожает symlinks/execute permissions. Release packager сохраняет эти архивы и добавляет notices; локальный smoke подтвердил execute bits нативных файлов, notices, обязательность source artifact и генерацию SHA256SUMS.

## Локально выполнено

- Flutter 3.47.9 / Dart 3.13.7: analyze без замечаний, 36 Flutter и 5 Python backend tests PASS.
- Официальный macOS sing-box 1.14.4: обе JSON-конфигурации check PASS; loopback routing smoke для обеих PASS. TUN не запускался, системные маршруты не менялись.
- Windows AWG helper: Go 1.26 cross-build Windows/amd64 PASS, без установки/запуска service.
- AWG Go CLI: cross-build Linux/amd64 PASS. AWG C tools: локальная компиляция PASS. Bash syntax check PASS.
- Source exporter: PASS, 598 native dependency modules, опубликованные core sources и Dart plugin sources; Go 1.27 использован для AndroidLibXrayLite dependency graph. Локальный archive был пробным; release получает архив точного CI source commit.
- Полный Xcode локально отсутствует, поэтому iOS/macOS native сборки подтверждены GitHub runners; Windows/Linux Flutter сборки также выполнялись на соответствующих runners.

Тесты проверяют импорт VLESS/AWG2, S/H/I без потерь, запрет hooks/insecure TLS, выбор/отзыв/истечение профиля, partial refresh, tombstone после перезапуска, очереди и приватность отчётов, disconnect во время проверки; Apple AWG MethodChannel и счётчики; native конфиги и routing; интерфейс на телефоне/планшете/desktop, 200% текст и reduced motion. Fake-channel tests не заменяют iPhone.

## Исправленные ошибки интеграции

- Отключена неиспользуемая Android-регистрация sing_box, вызывавшая duplicate gomobile go.Seq с Xray.
- AWG Go вынесен в отдельный Apple extension, исправлены source groups и library search paths Xcode.
- Сохранена первая default Keychain group существующего vault; VLESS/AWG native config exchange переведён в shared Keychain. Native plaintext config.json больше не записывается.
- Windows linker больше не добавляет конфликтующий asInvoker manifest к requireAdministrator.
- Фикстура HTTP возвращает Content-Length, чтобы тест маршрутизации не зависел от поведения TCP close на разных ОС.
- macOS bundle включает оба sing-box executable, выбор по Dart ABI; Apple архивы сохраняют структуру bundles.

## Не проверено и не заявляется готовым

По согласованию с пользователем нет отдельного тестового VPN-сервера и Apple Developer account. **Реальные подключения, установка на устройства и изменение VPN-маршрутов не выполнялись.** Успешная сборка не доказывает совместимость с выдаваемыми профилями. Нужен изолированный стенд AWG2/VLESS Reality: DNS/IPv6, split routing, Wi-Fi/LTE, сон/фон, отзыв/expiry и обновление с той же подписью.

Apple unsigned не устанавливается как IPA/TestFlight и не получает Network Extension entitlement. macOS ad-hoc не заменяет Developer ID/provisioning/notarization. Windows просит UAC; Linux нужны права/зависимости из [NATIVE_VPN](NATIVE_VPN.md). Установщиков, signed broker/XPC, crash supervisor/reconciliation и полноценного fail-closed kill switch нет.

Доменные исключения .ru/.рф/.su и ручные домены реализованы для VLESS; это эвристика, не список всех российских сайтов. Для AWG доменных исключений нет; app-исключения есть только на Android. При произвольных AWG AllowedIPs HTTPS + counters не доказывают привязку конкретной пробы к туннелю.

Android APK/AAB подписаны тестовым ключом. Постоянный production keystore не настроен: обновление требует той же подписи; новая подпись может потребовать переустановки и не гарантирует сохранение vault. Боевые API Telegram/платежи/quality collector не развёрнуты: реализованы контракт и reference backend. Отчёты отправляются только после согласия и настройки API. Не реализованы QR/vpn://, EN/светлая тема. Юридический/SBOM аудит всех транзитивных объектов и 16 KB pages остаются перед коммерческим распространением.

Действующие VPN-серверы и подключения компьютера не изменялись. Старый [0.1.0 preview](https://github.com/starscream001/vpn_app/releases/tag/v0.1.0-preview.1) сохранён.
