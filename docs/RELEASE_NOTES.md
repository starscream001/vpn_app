FoxWay VPN 0.2.0 preview: нативные адаптеры VLESS/Reality и AmneziaWG добавлены для iOS, Windows, Linux и macOS; Android сохранён. Утверждённый стиль рыжей лисы A и горного фона, Авто/VLESS/Amnezia, импорт сторонних профилей, защищённое хранилище и архитектура Telegram-подписок.

Проверено: 36 тестов Flutter + 5 API, native config validation и loopback routing tests, Android APK/AAB, iOS unsigned с двумя расширениями, Windows/Linux/macOS native bundles. Все 7 jobs run 42764187193 успешны; source commit 5bf8b7871fd7fee2a0851e138011f1c52cc3320a. Реальные VPN-подключения не выполнялись: тестового сервера и Apple-аккаунта пока нет.

Для современного Android: app-arm64-v8a-release.apk. APK/AAB используют тестовую подпись; постоянный production keystore ещё не настроен, обновления требуют одинаковой подписи.

Windows: распаковать весь архив, запуск запрашивает UAC. Linux: распаковать весь bundle; VLESS требует NET_ADMIN/NET_RAW/административного запуска, AWG использует pkexec и требует iproute2/resolvconf/iptables или nftables/polkit. macOS: оба core executable Intel/Apple Silicon включены, но для TUN/NE нужны права и подходящая Apple подпись; это не notarized consumer installer. iOS: unsigned Runner.app не является установочным IPA/TestFlight, нужна подпись приложения и обоих расширений.

Сайты .ru/.рф/.su напрямую и ручные домены — только VLESS, эвристика российских сайтов. Исключения приложений — Android. Полноценный kill switch, crash supervisor и production установщики ещё не реализованы. Telegram API — контракт и reference backend, без подключения боевого бота. Отчёты о рабочих серверах отправляются по согласию после настройки API, без ключей/сайтов/списка приложений.

Corresponding sources и notices входят в релиз; архив исходников около 1.13 GB. GPL-компоненты распространяются с соответствующими лицензиями. SHA256SUMS.txt относится ко всем файлам этого релиза. Действующие VPN-серверы не изменялись.

Точные проверки, инструкции и ограничения: https://github.com/starscream001/vpn_app/blob/main/docs/VALIDATION.md

Тег релиза включает последующую документацию и workflow публикации; файлы приложения совпадают с проверенным source commit. Это автоматически проверяется перед публикацией.
