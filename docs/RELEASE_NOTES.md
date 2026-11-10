FoxWay VPN: первая предварительная версия с рыжей лисой A и горным фоном.

Android: адаптеры AmneziaWG и VLESS/Reality, импорт, исключения, Авто, защищённое хранилище и архитектура Telegram API. Реальное VPN-соединение на устройстве ещё не проверено. APK/AAB подписаны тестовым ключом; постоянный production signing ещё не настроен.

Windows, Linux, macOS: пока интерфейс, импорт и хранилище БЕЗ VPN-туннеля. iOS: unsigned Runner.app, также БЕЗ VPN-туннеля; это не установочный IPA и не TestFlight.

Все пять платформ действительно собраны в GitHub Actions, 35 тестов прошли. Артефакты взяты из успешного run 42716650329, commit eded064f66e92e5731f3196fd17791577b790bc1. SHA256SUMS.txt относится к файлам этого релиза.

Для большинства современных Android-телефонов: app-arm64-v8a-release.apk. Остальные APK: armeabi-v7a, x86_64 и universal. Для iOS и desktop системные туннели разрабатываются следующим этапом.

Действующие VPN-серверы не изменялись. Документация: https://github.com/starscream001/vpn_app/blob/main/docs/VALIDATION.md
