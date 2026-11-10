# Native VPN development (0.2.0)

Добавлены iOS Packet Tunnel Extension (sing-box/libbox) и desktop TUN process для VLESS/Reality. Это экспериментальная разработка поверх проверенного релиза 0.1.0: реальные подключения ещё не проверены. [Матрица, права и ограничения](docs/NATIVE_VPN.md).

# FoxWay VPN

Flutter-клиент в стиле утверждённого макета: рыжая лиса A, тёмные горы, бирюзовые акценты, одна кнопка. Репозиторий полностью заменяет прежнюю HTML-страницу.

**Статус опубликованного релиза 0.1.0: Android preview, не готовый коммерческий релиз.** Код адаптеров AmneziaWG и VLESS/Reality подключён к реальным библиотекам; реальное VPN-соединение ещё необходимо проверить на отдельном устройстве и тестовом сервере. Действующие серверы при разработке не изменялись. На iOS/Windows/macOS/Linux пока доступны интерфейс, импорт и хранилище, кнопка системного VPN отключена.

![FoxWay](assets/fox-icon.png)

## Что реализовано

- Общий Flutter-проект для Android, iOS, Windows, macOS, Linux.
- Android: AmneziaWG через `com.zaneschepke:amneziawg-android:2.3.7`; VLESS TCP + Reality/TLS через `flutter_v2ray:2.0.0` и Xray.
- Переключатель Авто / VLESS / Amnezia, выбор профиля, удаление, последовательный ограниченный перебор кандидатов.
- Импорт из буфера, файла, HTTPS-подписки; plain/base64 VLESS, AWG `.conf`, поля AWG 2.0 сохраняются без преобразования в обычный WireGuard. `vpn://` Amnezia-контейнеры и QR пока не поддержаны.
- Android-исключения приложений для обоих движков; VLESS-исключения доменов, `.ru`, `.рф`, `.su` напрямую по умолчанию. Это доменная эвристика, не полный список российских сайтов. Для AWG доменные исключения пока не реализованы и интерфейс сообщает об этом.
- HTTPS-проверка и рост RX/TX; VLESS использует принудительный proxy inbound, чтобы собственный трафик приложения не проверял прямой интернет вместо VPN.
- Зашифрованное хранилище профилей/токенов/очереди: стабильный app ID и ключ `foxway.state.v1`. Обновление с той же подписью сохраняет данные; удаление приложения не гарантирует сохранность. Ошибка чтения не очищает хранилище.
- Частичное обновление каталога сохраняет отсутствующие профили; явный отзыв и срок действия имеют приоритет над последним успехом.
- API привязки одноразовым кодом, обновления каталога и отчётов; отдельный reference backend с SQLite, без управления VPN-серверами.
- Отчёты по согласию: только профили FoxWay, идентификатор, протокол, результат, задержка и счётчики. Очередь до 100, пакеты по 20, повтор при следующем цикле. Ключи, сайты и приложения не отправляются.
- Автотесты логики, интерфейса и API; Actions для всех пяти платформ. Неравенство возможностей платформ указано в именах артефактов.

## Разработка

Требуются Flutter **3.47.9**, Java 21, Android SDK 36 и NDK 28.2.13676358. Android minSdk 26. На Mac для Apple-сборок нужны полный Xcode и CocoaPods, одних Command Line Tools недостаточно.

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test --coverage
python3 -m unittest discover -s backend -v
flutter build apk --debug
```

Сборки остальных платформ: `flutter build windows`, `flutter build macos`, `flutter build linux`, `flutter build ios --release --no-codesign` на соответствующей ОС. Для Linux установить `clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libjsoncpp-dev libssl-dev`.

GitHub Actions сохраняет Android APK/AAB с тестовой подписью, desktop bundles и неподписанный Runner.app iOS. Это тестовые артефакты, не установщики для магазинов. Для выпуска обязательно заменить Android signing config и сохранить release keystore: смена подписи нарушает обновления и доступ к прежним данным.

## Проверенные сборки

[GitHub Actions: все jobs успешны](https://github.com/starscream001/vpn_app/actions/runs/42716650329). 30 Flutter tests + 5 backend tests, Android APK/AAB, Windows/Linux/macOS release bundles и iOS unsigned. Это подтверждение сборки; границы VPN-поддержки указаны выше. [Точные результаты и артефакты](docs/VALIDATION.md).

## Документация

- [Архитектура и сценарии](docs/ARCHITECTURE.md)
- [Подписки Telegram и API](docs/API.md)
- [Лицензии и выбор основы](docs/LICENSES.md)
- [iOS и подпись](docs/IOS.md)
- [Проверки и ограничения](docs/VALIDATION.md)

## Следующий этап перед распространением

Прогнать Android на изолированном AWG 2.0 и VLESS/Reality стенде, проверить DNS/IPv6, split tunneling, Wi-Fi/LTE, сон, отзыв ключа, восстановление процесса, 16 KB memory pages и foreground service. Подключить API действующего бота через отдельный адаптер после согласования адреса и контракта. Затем реализовать Network Extension на iOS и привилегированные desktop helpers. Ни один из этих пунктов не считается выполненным только на основании успешной компиляции.
