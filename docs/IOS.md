# iOS: сборка и публикация

Actions выполняет `flutter build ios --release --no-codesign` и сохраняет Runner.app. Runner.app содержит PacketTunnel (VLESS/libbox) и AWGPacketTunnel (AmneziaWG Go). Компиляция не подтверждает работу VPN на устройстве; это неподписанный .app, не IPA для установки. Apple-аккаунта пока нет, поэтому CI не использует сертификаты.

Для реального iOS VPN нужно:

1. Проверить уже добавленные targets PacketTunnel и AWGPacketTunnel на физическом iPhone. Каждый движок работает в своём NEPacketTunnelProvider; Go bridge AWG компилируется перед Flutter-командой, как в build.yml.
2. Зарегистрировать bundle IDs app.foxway.foxway, app.foxway.foxway.PacketTunnel и app.foxway.foxway.AWGPacketTunnel, App Group group.app.foxway.foxway, включить capability Network Extensions / packet-tunnel-provider и App Groups в приложении и обоих расширениях. Профили provisioning должны включать соответствующие entitlements.
3. В Xcode выбрать одинаковую Team для всех трёх targets. Сохранить default Keychain group первой и добавить общий $(AppIdentifierPrefix)app.foxway.shared. При смене bundle IDs обновить также Swift providerBundleIdentifier, capabilities и libbox options.
4. Создать Apple Distribution certificate и App Store provisioning profiles, хранить .p12 и пароль только в GitHub Secrets. Не коммитить сертификаты, provisioning и private keys.
5. После настройки подписи собирать `flutter build ipa --release --export-options-plist=...`, архивировать dSYM, загружать в TestFlight и проверять на iPhone, затем проходить App Review.

Членство Apple Developer Program стоит 99 USD в год или местный эквивалент, а не разовый «сертификат»; условия/доступность зависят от страны. [Apple enrollment](https://developer.apple.com/help/account/membership/program-enrollment/).

Правило 5.4 требует для VPN приложений NEVPNManager API, аккаунт организации, раскрытие обработки данных и соблюдение местных требований. Ознакомиться с [актуальными App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#vpn-apps). При включении диагностических отчётов передавать минимум данных и раскрывать обработку до использования. Оплата/продление через Telegram не означает автоматического разрешения обходить правила Apple о платежах; модель распространения согласовать до публикации.

На iOS пользовательский выбор исключений отдельных приложений недоступен обычному потребительскому VPN как на Android; per-app VPN связан с управляемой конфигурацией/MDM. Нельзя переносить Android переключатель без реализации и проверки платформенных ограничений.

## macOS

AWGPacketTunnel использует ту же shared Keychain схему. Unsigned CI и ad-hoc подпись не дают разрешения на Network Extension: нужны подходящие Developer ID/provisioning, entitlements для app/extension и notarization. VLESS пока process/TUN вне App Sandbox, не Mac App Store вариант. Никакие сертификаты и аккаунты автоматически не создаются.
