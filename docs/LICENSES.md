# Выбор основы и лицензии

Проверено 10 ноября 2026. Это технический учёт, не юридическое заключение.

Hiddify не использован. [LICENSE.md](https://github.com/hiddify/hiddify-app/blob/main/LICENSE.md) содержит дополнения к GPLv3: NonCommercial без письменного согласия, обязательный GitHub fork, Actions releases, attribution и ShareAlike. Называть это обычной GPL и молча встраивать в платный FoxWay было бы неверно. Код Hiddify и его ресурсы не копировались. Публичное заявление поддержки AmneziaWG не доказывает совместимость с конкретными AWG 2.0/3.1 профилями.

| Компонент | Версия / источник | Условия |
|---|---|---|
| Flutter | 3.47.9 | BSD-3-Clause и notices SDK |
| flutter_v2ray | 2.0.0, pubspec.lock | MIT, текст сохранён |
| Xray-core | транзитивно через AndroidLibXrayLite v26.10.17 | MPL-2.0; сохранять уведомления и доступ к исходникам покрытых файлов |
| AndroidLibXrayLite | v26.10.17 | LGPL-3.0; условия замены/перелинковки и соответствующие исходники проверить перед распространением бинарников |
| amneziawg-android | com.zaneschepke 2.3.7 Maven Central | POM указывает Apache-2.0; Java headers Apache-2.0 |
| amneziawg-go | нативная транзитивная часть AWG AAR | MIT; отдельные native dependencies требуют полного binary SBOM |
| Inter | variable font из google/fonts | SIL OFL 1.1, текст сохранён |
| fox-icon / fox-mountains | восстановлены генерацией по пользовательскому референсу | Не Hiddify assets; не пиксельное извлечение оригинала |

Источники: [AWG Android](https://github.com/amnezia-vpn/amneziawg-android), [AWG Maven POM](https://repo.maven.apache.org/maven2/com/zaneschepke/amneziawg-android/2.3.7/amneziawg-android-2.3.7.pom), [AWG Go license](https://github.com/amnezia-vpn/amneziawg-go/blob/master/LICENSE), [Flutter plugin](https://github.com/blueboy-tm/flutter_v2ray), [AndroidLibXrayLite](https://github.com/2dust/AndroidLibXrayLite), [Xray-core](https://github.com/XTLS/Xray-core).

Собственный код FoxWay распространяется под MIT (корневой LICENSE). Это не заменяет лицензии зависимостей. Перед коммерческим release необходимо включить полный набор notices всех транзитивных .so/AAR, зафиксировать исходники ядер, проверить требования LGPL к способу поставки, воспроизводимость и Google Play 16 KB pages. Текущий проект — preview; юридическая готовность бинарного релиза не заявлена.

## Изменения 0.2.0

Подключён sing_box 1.0.0 (GPL-3.0-or-later) для iOS Network Extension и официальный sing-box 1.14.4 для desktop. Собственный MIT-код совместим с GPL; условия распространения **собранного приложения, включающего GPL-компоненты, — GPL**, с соответствующими исходниками и build scripts. Запрета платных подписок GPL не содержит. Это не Hiddify. Пакет desktop core закреплён по URL/version и SHA-256 в scripts/sing_box_assets.json; Apple XCFramework проверяется по SHA в upstream Package.swift. Сборка corresponding-source bundle с ядрами, Go-модулями, Dart-плагинами и notices обязательна для релиза 0.2: [состав и команды](SOURCES.md). AWG Apple/Windows/Go — MIT, AWG tools — GPL-2.0, тексты сохранены.
