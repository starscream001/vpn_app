# Обновление приложения

## Проверка и доверие

`UpdateService` проверяет GitHub Releases при запуске UI и каждые 6 часов. Ручная проверка — «Ещё → Обновления». Сетевой сбой не препятствует использованию установленной версии. Semver учитывает числовые компоненты, preview и build metadata. Preview build по умолчанию видит предварительные релизы; production собирать с `--dart-define=UPDATE_CHANNEL=stable`.

Release JSON приходит только с фиксированного GitHub API репозитория starscream001/vpn_app. Asset URL обязан принадлежать его releases/download/tag. HTTP/чужой repository/userinfo/опасные имена отвергаются. Редиректы допускаются только на HTTPS GitHub asset hosts. Ограничены размеры ответов, число редиректов и timeout. Секреты VPN или API не добавляются в запросы обновления.

После нажатия «Скачать» клиент читает SHA256SUMS этого же release, требует ровно одну сумму для выбранного asset и потоково скачивает файл с лимитом 512 MB в отдельный temp-каталог. Только после SHA-256 появляется готовый файл без `.part`. Ошибка удаляет непроверенную загрузку. Архив исходников не выбирается как обновление.

Checksum защищает от повреждения и связывает asset с release manifest, но **не является независимой подписью издателя**: доверие к GitHub/TLS/учётной записи оператора остаётся. Production требует code signing и защищённого release pipeline. TLS verification не отключается.

## Android

Выбирается APK для текущего ABI. Native часть принимает файл только из cache приложения, сверяет package ID, возрастающий versionCode и signing certificates с установленным приложением. Несовпадение прекращает установку без очистки данных. Затем открываются системное разрешение unknown sources и штатный installer через FileProvider с узким cache-path.

Это не скрытая установка. Отмена системного диалога оставляет прежнюю версию. Google Play release следует вести через Play In-App Updates/магазинный канал и соответствующий policy manifest, а не публиковать sideload permission без проверки Play policy. Текущий preview — direct APK distribution.

Подпись CI:

- Preview: временная тестовая подпись, без обещания совместимости обновлений. Private signing keys не помещаются в CI cache. Для надёжных обновлений нужно настроить постоянную production подпись.
- Production: задать secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Keystore создаётся в runner temp, в Git не коммитится. Увеличивать build number в pubspec при каждом устанавливаемом выпуске.
- Старый 0.2 preview использовал иной ephemeral key. Автоматический переход с него может быть невозможен: клиент откажет по signature. Не удалять данные автоматически; сохранить/переимпортировать свои ссылки осознанно. Постоянный production ключ должен сохраняться оператором в защищённом backup и GitHub Secrets, вне публичных artifacts/cache.

## Windows и Linux

После загрузки пользователь подтверждает установку и перезапуск. Из текущего bundle копируется небольшой собственный updater в temp. Он независимо сверяет SHA-256, проверяет zip paths/duplicate entries/symlinks/размеры/полноту и извлекает новый bundle в отдельный staging **рядом с установкой**. Пока всё не подготовлено, клиент не закрывается: helper посылает READY.

После READY приложение останавливает собственный core (не снимая активный desktop guard) и завершает свой процесс. Helper ждёт только его PID до 120 секунд. Затем текущая папка переименовывается в `.previous-<id>`, staging занимает её место, запускается новая версия. Vault в AppData/libsecret и прочие OS credentials не входят в эту операцию. Linux требует Python 3; Windows использует PowerShell без изменения глобальной execution policy. Нужны права записи в parent installation directory.

Если prepare/validation не удались, приложение остаётся открытым. При ошибке rename/start helper возвращает предыдущий bundle, когда это возможно, и запускает его. Если питание пропало между операциями или helper аварийно погиб, автоматический crash recovery marker не реализован: прежний bundle остаётся рядом, требуется ручное восстановление. Предыдущая версия не удаляется автоматически; откат всегда целым bundle, не одним exe. Мгновенный exit 0 нового процесса не является полноценным health check.

Нативное закрытие/переименование настоящей установки пока не проверялось на Windows/Linux устройствах. Unit tests проверяют безопасный архив и отказы; CI проверяет Windows script syntax и bundles. Подпись установщика, отдельный updater broker и production installer package остаются перед массовым распространением.

## macOS

Приложение проверяет и скачивает macOS zip, открывает его расположение в Finder. **Текущий unsigned/ad-hoc preview не выполняет автоматическую замену подписанного приложения.** Для полноценной автоустановки нужен Developer ID/notarization, проверка одной Team ID у новой версии и signed updater (например отдельный подписанный helper или Sparkle с EdDSA feed). Замена установленной NE app unsigned архивом может лишить VPN прав, поэтому такой путь не выдаётся за готовый auto-install.

Общий manifest/download слой уже работает для macOS, профили остаются в Keychain. Существующий bundle содержит native cores Intel/Apple Silicon; архив ditto сохраняет symlinks и execute bits.

## iOS

Автопроверка новых версий доступна, но установка идёт через App Store/TestFlight. Для этого задать `--dart-define=IOS_UPDATE_URL=https://apps.apple.com/...` либо `https://testflight.apple.com/...`; другие hosts не принимаются. Пока Apple account отсутствует, адрес не выдумывается и unsigned Runner.app не предлагается в качестве установочного обновления. ОС может обновлять App Store приложение по пользовательской настройке магазина.

## VPN во время обновления

Проверка/загрузка идут через текущую маршрутизацию, без отдельного обходного VPN/DNS канала. Если strict guard удерживает сеть, updater не снимает его, чтобы обратиться к GitHub. Windows/Linux сохраняют desktop guard во время замены; после перезапуска подключитесь либо явно разрешите интернет. Android/iOS контролируют lifecycle обновления на уровне ОС. Проверить этот сценарий с постоянной подписью обязательно на отдельном устройстве.

При ручном откате на старую версию без native guard сначала явно снимите защиту: старый UI может не знать о новых WFP/nft/PF правилах. Для аварии используйте только адресные действия из PROTECTION.md.
