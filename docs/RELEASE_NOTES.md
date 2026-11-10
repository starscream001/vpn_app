FoxWay VPN 0.3 preview — обновления приложения, session kill switch и существующая Telegram-подписка.

Что добавлено:
- Новый README со скриншотами, матрицей платформ и пользовательскими инструкциями.
- @Ilyavpnadmin_bot → прежняя HTTPS-ссылка → импорт в FoxWay. Автообновление списка раз в 15 минут, mixed feed/expiry/cache. Сам бот и VPN-серверы не изменялись.
- Проверка GitHub Releases при запуске и раз в 6 часов, Semver, allowlist URL и SHA-256. Android installer сверяет signer; Windows/Linux — staged bundle replacement после подтверждения, предыдущая версия для отката. macOS пока загружает проверенный архив; iOS требует App Store/TestFlight.
- Strict session protection: Android OS lockdown, Apple NE options/On Demand, persistent Windows WFP, Linux nft, macOS PF. Неудачная проверка не снимает desktop guard; исключения временно не применяются. На Apple строгий режим не меняет provider автоматически.

Проверено: 49 Flutter + 16 Python tests, native config/routing smoke, сборки Android/iOS/Windows/macOS/Linux, corresponding-source archive. Все 7 jobs run 42800991614 успешны. Бинарники собраны из ad803c7d9bc8df3a1904cc3cef8e3b45e2efcede; тег дополнительно включает только документацию и release workflow, совпадение приложения проверяется перед публикацией.

Для современного Android: app-arm64-v8a-release.apk. **Подпись пока тестовая**; постоянный ключ ещё не сохранён в GitHub Secrets. Старые preview APK могут иметь несовместимый signer, автоматической очистки данных нет. Для надёжных обновлений нужен один постоянный signing key и возрастающий build number.

**Это preview, не подтверждённый security release.** Реальный VPN и kill-core/GUI leak checks на устройствах не выполнялись; WFP/nft/PF не применялись к компьютеру пользователя. Для Apple нет account/provisioning: unsigned .app не является установочным IPA/TestFlight, macOS ad-hoc не заменяет Developer ID/notarization. Нужны права/зависимости для desktop; macOS PF требует стандартный layout и при активации закрывает существующие соединения. Boot-time protection, полный process supervisor, crash/power-loss recovery установщика и signed production updater ещё требуют доработки/стенда.

Новый bearer API/quality collector не развёрнут. Действующая подписка бота работает через прежние ссылки и сама по себе не включает отправку отчётов.

SHA256SUMS, исходники зависимостей/ядер (~1.13 GB) и notices входят в релиз. Все возможности, восстановление сети и ограничения: https://github.com/starscream001/vpn_app/blob/main/docs/VALIDATION.md
