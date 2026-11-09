# iOS: сборка и публикация

Actions выполняет `flutter build ios --release --no-codesign` и сохраняет Runner.app. Это компиляция оболочки; артефакт нельзя считать подписанным IPA или готовым VPN-клиентом. Packet Tunnel Provider в текущем проекте отсутствует.

Для реального iOS VPN нужно:

1. Реализовать отдельный Network Extension target с NEPacketTunnelProvider и native bridge к совместимым лицензированным ядрам AWG/Xray. Dart-код не исполняется вместо iOS Packet Tunnel Provider.
2. Зарегистрировать bundle IDs приложения и расширения, App Group, включить capability Network Extensions / packet-tunnel-provider и App Groups в обоих targets. Профили provisioning должны включать соответствующие entitlements.
3. В Xcode выбрать Team и Signing для обоих targets, настроить Keychain/App Group для передачи конфигурации без plaintext файлов.
4. Создать Apple Distribution certificate и App Store provisioning profiles, хранить .p12 и пароль только в GitHub Secrets. Не коммитить сертификаты, provisioning и private keys.
5. После реализации расширения собирать `flutter build ipa --release --export-options-plist=...`, архивировать dSYM, загружать в TestFlight и проверять на iPhone, затем проходить App Review.

Членство Apple Developer Program стоит 99 USD в год или местный эквивалент, а не разовый «сертификат»; условия/доступность зависят от страны. [Apple enrollment](https://developer.apple.com/help/account/membership/program-enrollment/).

Правило 5.4 требует для VPN приложений NEVPNManager API, аккаунт организации, раскрытие обработки данных и соблюдение местных требований. Ознакомиться с [актуальными App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#vpn-apps). При включении диагностических отчётов передавать минимум данных и раскрывать обработку до использования. Оплата/продление через Telegram не означает автоматического разрешения обходить правила Apple о платежах; модель распространения согласовать до публикации.

На iOS пользовательский выбор исключений отдельных приложений недоступен обычному потребительскому VPN как на Android; per-app VPN связан с управляемой конфигурацией/MDM. Нельзя переносить Android переключатель без реализации и проверки платформенных ограничений.
