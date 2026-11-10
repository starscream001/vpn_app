# Итоговые проверки — 10 ноября 2026

Проверенный commit: `eded064f66e92e5731f3196fd17791577b790bc1`. [Финальный GitHub Actions run](https://github.com/starscream001/vpn_app/actions/runs/42716650329) — **success**. Все шесть jobs завершены успешно; артефакты реально загружены.

| Проверка | Результат |
|---|---|
| Dart format / flutter analyze | PASS, без замечаний |
| Flutter unit/widget tests | 30 PASS |
| Backend unit tests | 5 PASS |
| Android | debug APK, universal release APK, три ABI APK и AAB — PASS |
| Windows x64 | release bundle — PASS |
| Linux x64 | release bundle — PASS |
| macOS | release app bundle — PASS |
| iOS | release --no-codesign Runner.app — PASS |

## Артефакты финального прогона

- [Android APK/AAB, тестовая подпись](https://github.com/starscream001/vpn_app/actions/runs/42716650329/artifacts/13718757836)
- [Windows UI preview](https://github.com/starscream001/vpn_app/actions/runs/42716650329/artifacts/13719675087)
- [Linux UI preview](https://github.com/starscream001/vpn_app/actions/runs/42716650329/artifacts/13719390345)
- [macOS UI preview](https://github.com/starscream001/vpn_app/actions/runs/42716650329/artifacts/13719630443)
- [iOS unsigned UI preview](https://github.com/starscream001/vpn_app/actions/runs/42716650329/artifacts/13719315917)
- [Coverage и снимок интерфейса](https://github.com/starscream001/vpn_app/actions/runs/42716650329/artifacts/13717579703)

Артефакты Actions истекают 7 февраля 2027 по данным GitHub; скачивание может требовать входа. Android arm64 APK около 70.9 MB, armeabi-v7a 66.7 MB, x86_64 75.2 MB, universal 191.8 MB, AAB 120.7 MB (Flutter output). Подписи тестовые. Для будущих обновлений из магазина обязателен постоянный release keystore.

## Локальные проверки

Flutter 3.47.9 / Dart 3.13.7, Java 21, Android SDK 36, NDK 28.2.13676358, CMake 3.22.1. Те же 30 Flutter и 5 backend tests прошли локально, анализатор без замечаний. Android debug/release, три ABI APK и AAB также собраны локально.

Отдельный HTTP smoke на временном loopback стенде подтвердил: обмен одноразового кода → авторизованный каталог → сохранение отчёта в SQLite. Использовались фикстуры, не настоящий Telegram и не действующие VPN-серверы.

Widget tests: 390×844, 844×390, 1100×800, текст 200% и reduced motion. Снимок главной страницы просмотрен визуально. Проверяются импорт, AWG 2 поля, Reality, запрет hooks/insecure TLS, partial refresh, expiry/revocation, сохранение tombstone после перезапуска, неверный каталог, очередь и приватность отчётов, ручной disconnect во время quality probe.

## Исправленные проблемы сборки

1. Hiddify исключён из основы из-за опубликованных NonCommercial/дополнительных условий; использованы независимые библиотеки.
2. Shallow checkout Flutter в CI без semver tag определял SDK как 0.0.0-unknown. У фиксированного upstream commit восстановлены соответствующий tag 3.47.9 и stable branch. Проверка lockfile сохранена.
3. macOS 14 runners удалены GitHub 2 ноября 2026; использован macOS 15.
4. Явно настроены Android SDK и CMake. Setup action больше не пытается установить удалённый Google пакет `tools`.
5. Устранён конфликт META-INF OSGI manifest в Java dependency packaging.
6. Локальный apkanalyzer требовал физически корректный SDK layout и Java 21. AAB stripping check пройден без отключения проверок.

CI runs до финального результата сохраняют историю ошибок; итоговый run выше зелёный. Документационный коммит после него помечен skip ci: исходный код приложения и workflow после проверенного SHA не меняются.

## Непроверенное и отсутствующее

Реальное VPN-подключение не выполнялось: отдельное тестовое устройство и тестовый endpoint не предоставлены. Наличие настоящих адаптеров, успешная компиляция и fake-engine tests не доказывают совместимость с выдаваемыми вами профилями. Нужен Android-стенд AWG 2.0/VLESS Reality, DNS/IPv6 leak checks, split routing, Wi-Fi/LTE, sleep/background, процесс/revoke/expiry и обновление с той же подписью.

iOS/desktop — **интерфейс, импорт и хранилище без системного VPN**; на этих платформах кнопка VPN отключена. Network Extension и desktop privileged helpers ещё предстоит реализовать. iOS unsigned не является установочным IPA/TestFlight.

Российские домены напрямую реализованы только для VLESS (.ru/.рф/.su + ручные домены); AWG IP/DNS route manager отсутствует. ECH/CDN и российские сайты на других доменах требуют отдельных правил и тестов.

Настоящий API бота и quality collector не развёрнуты; контракт и reference backend готовы. Не реализованы QR/vpn://, полноценный native always-on/kill switch, native state reconciliation после перезапуска, фоновые проверки во сне, светлая тема и EN. Перед коммерческим распространением нужен полный binary license/SBOM аудит, production signing и проверка 16 KB native pages.

Действующие VPN-серверы и подключения компьютера не изменялись. Реальные платежи, публикация в магазинах и доступ к Telegram bot token не выполнялись.
