# Проверки и ограничения

Дата: 10 ноября 2026. Проверки выполняются в ходе реализации; окончательные результаты CI будут записаны следующим коммитом.

- Flutter 3.47.9 / Dart 3.13.7 установлен в изолированный рабочий каталог.
- `flutter analyze`: без замечаний.
- `flutter test --coverage`: 27 тестов прошли, включая 390×844, 844×390, 1100×800, текст 200% и reduced motion.
- `python3 -m unittest discover -s backend -v`: 5 тестов прошли.
- Android debug build: выполняется с локальными Java 21 и Android SDK; исходная Java 11 из Android Studio несовместима, устранено выбором Java 21 для Gradle.
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
