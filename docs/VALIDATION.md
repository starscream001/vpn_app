# Проверки и ограничения

Дата: 10 ноября 2026. Проверки выполняются в ходе реализации; окончательные результаты CI будут записаны следующим коммитом.

- Flutter 3.47.9 / Dart 3.13.7 установлен в изолированный рабочий каталог.
- `flutter analyze`: без замечаний.
- `flutter test --coverage`: 30 тестов прошли, включая 390×844, 844×390, 1100×800, текст 200% и reduced motion.
- `python3 -m unittest discover -s backend -v`: 5 тестов прошли.
- Android debug build: успешно, `build/app/outputs/flutter-apk/app-debug.apk`. Найдены и исправлены конфликт Java resources и отсутствие CMake 3.22.1. Использованы Java 21, SDK 36, NDK 28.2.13676358. Исходная Java 11 несовместима; выбор Java 21 решает это.
- Xcode: доступен только `/Library/Developer/CommandLineTools`; локальная iOS/macOS компиляция невозможна без полного Xcode. Настроены Actions на macOS.
- Windows/Linux: проверяются на соответствующих runners, локальный host macOS их не компилирует.

Настоящие AWG/VLESS-сессии не выполнялись: отдельный тестовый VPN endpoint и устройство не предоставлены. Действующие VPN-серверы не менялись, существующие VPN-подключения компьютера не переключались. Успешный тест с fake engine проверяет state machine, а не совместимость реального протокола.

## Обязательный ручной стенд перед релизом

- AWG 2.0: S1–S4, H1–H4 ranges, I1–I5, handshake, HTTPS и RX/TX, DNS, IPv4/IPv6.
- VLESS TCP Reality: SNI/public key/short id/flow, HTTPS по принудительному proxy inbound, отказ при неверном ключе.
- Android: VPN consent/отказ, background/sleep, notification stop, Wi-Fi→LTE→Wi-Fi, airplane mode, перезапуск процесса, обновление APK той же подписью.
- Исключённое приложение идёт напрямую; включённое через VPN. Домены .ru/.рф/.su и ручные исключения VLESS идут напрямую, остальные через VPN. Проверить ECH/CDN/IPv6/QUIC и утечки DNS отдельно.
- Отзыв профиля и expiry отключают платный профиль; offline refresh оставляет рабочую конфигурацию; сторонние профили не зависят от FoxWay оплаты.
- Очередь отчётов сохраняется при HTTP 500/offline, отправляется после восстановления, выключение очищает. На сервере нет ключей, URL или списка приложений.
- iOS: после реализации extension — device install/TestFlight, VPN entitlements и подписи обоих targets; unsigned Runner.app этого не проверяет.

В CI Flutter загружается из исходников фиксированного commit `c197ca5199e9ee5661e865596c9c07294dfab51c`: публичный JSON index архивов SDK в текущей сети возвращает HTTP 404. Использован тот же способ bootstrap, что успешно выполнен локально.

Первый CI run 42714390770 выявил, что shallow checkout SDK без semver tag определяется как Flutter 0.0.0-unknown. Исправлен bootstrap: фиксированный upstream commit помечается соответствующим ему тегом 3.47.9 и stable branch. Lockfile enforcement сохранён.

Android release APK также собран локально (universal, 191.8 MB по Flutter). Для удобства добавлена отдельная arm64 сборка через --split-per-abi. Второй run 42714840462 прошёл checks; macOS 14 runner больше не поддерживается (удалён GitHub 2 ноября 2026). Workflow переведён на macOS 15.

Финальная локальная проверка: 30 Flutter tests + 5 backend tests PASS; flutter analyze без замечаний; отдельный loopback HTTP smoke (exchange/catalog/report persistence) PASS. Исправлена гонка, при которой окончание quality probe после ручного отключения могло вызвать автоподключение; есть регрессионный тест. Ожидание системного VPN consent больше не обрывается внешним timeout с продолжением старого native start.

Собраны release APK для armeabi-v7a (66.7 MB), arm64-v8a (70.9 MB), x86_64 (75.2 MB), и AAB (120.7 MB), значения из Flutter output. Для AAB потребовалась корректная физическая установка cmdline-tools в изолированный SDK, не symlink за пределы SDK: apkanalyzer иначе не находил SDK. С защитами stripping всё успешно; обход проверки не использовался.

Run 42715189688: checks, Windows, Linux и iOS unsigned успешно. macOS ещё выполняется. Android CI выявил отсутствие sdkmanager в PATH; добавлен setup-android перед установкой CMake. Результат следующего прогона будет записан отдельно. CI не отменяет уже запущенные сборки при следующем push, чтобы не терять результаты долгих Apple-сборок.
