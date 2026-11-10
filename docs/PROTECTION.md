# Защита при обрыве: механизм и восстановление

Килл-свитч здесь означает защиту **VPN-сессии** от случайного выхода трафика напрямую после отказа движка. Это не защита от администратора/вредоносного ПО на устройстве и не обещание недоступности всех системных каналов ОС. Режим включается отдельно, применяется при подключении и требует нативных прав. Ошибка активации не считается успешной защитой.

При включении пользователь подтверждает: исключения сайтов и приложений временно не действуют, существующие соединения могут закрыться, после аварии сеть может остаться заблокированной. Сохранённые настройки split tunneling не стираются и вернутся после выключения строгого режима.

## Общий порядок

1. Проверить входной профиль; заранее разрешить адреса ограниченного набора кандидатов. DNS-подготовка до первого arm не является защищённой VPN-сессией.
2. Установить native guard до старта core. При ошибке не запускать core как будто защита есть.
3. Запустить owned tunnel и привязать firewall к его интерфейсу, если это требуется платформе.
4. Проверить HTTPS/counters. Неудачный probe, stop core и автоматический failover **не снимают desktop guard**.
5. Только явное действие пользователя освобождает защиту. При ошибке снятия UI получает ошибку; успешное снятие не выдумывается.

После падения GUI на desktop правила могут остаться без живого VPN. Это ожидаемый fail-closed эффект: открыть FoxWay → «Ещё» → «Отключить VPN и разрешить интернет». На Android блокировкой распоряжается сама ОС.

## Android

Используются Always-on VPN + Block connections without VPN. Пользователь включает оба режима в системных настройках; приложение не может честно включить lockdown одним Flutter-переключателем. AWG service больше не opts out из always-on. Перед защищённым start проверяются публичные `VpnService.isAlwaysOn/isLockdownEnabled` через Context/UID приложения; при неподтверждённом lockdown start отклоняется с инструкцией. Проверка доступна Android 10+; на Android 8/9 обычный VPN работает, а строгий режим не объявляется подтверждённым.

Системные ограничения сохраняются при гибели процесса. Восстановление реального подключения после reboot/upgrade ещё требует нативного стенда; приложение не обещает автоматический reconnect до открытия UI. Явное отключение в приложении открывает системные настройки: оно **не может программно отменить Android lockdown**. Пока пользователь не выключит «Блокировать без VPN», обычного интернета может не быть.

Справка: [Android VPN](https://developer.android.com/develop/connectivity/vpn), [VpnService](https://developer.android.com/reference/android/net/VpnService).

## iOS и macOS AmneziaWG

Для libbox VLESS на iOS передаются `includeAllNetworks=true`, On Demand, `excludeLocalNetworks=false`, `excludeAPNs=false`. AWG использует такие же NE параметры в собственном manager; конфигурация в shared Keychain. On Demand включает правило connect на любой сети.

При строгом режиме wrapper не останавливает это расширение при каждом failed probe и не переключает сервер/протокол автоматически: удерживает текущий provider и оставляет повторные соединения системе. Смена provider требует явного отключения пользователем. Явный stop сначала снимает On Demand в preferences, затем останавливает туннель.

Apple всегда оставляет исключения для некоторых системных потоков, например DHCP/captive portal/части cellular/companion traffic. Это не абсолютная блокировка устройства. Unsigned build не получает NE-права: для проверки нужны Team/provisioning и физическое устройство. После перезапуска GUI требуется дополнительно проверить native reconciliation на стенде.

Справка: [Apple includeAllNetworks](https://developer.apple.com/documentation/networkextension/nevpnprotocol/includeallnetworks), [Routing VPN traffic](https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic).

## Windows

`foxway-awg.exe guard-arm/guard-bind/guard-off` управляет собственными WFP объектами. Provider/sublayer/filter имеют фиксированные FoxWay keys и persistent flags; установка/замена фильтров транзакционна. Закрытие короткоживущего helper не освобождает фильтры.

Разрешены только native core executable paths, loopback, собственный TUN и необходимый DHCP/NDP. Flutter GUI не освобождён от фильтрации. Сначала применяется guard без TUN, затем bind к LUID собственного `FoxWayVless` или `FoxWay-<user hash>`. Старые правила заменяются атомарно. Старт/stop службы AWG по-прежнему затрагивает только собственное имя.

Постоянные объекты переживают core/GUI/service exit, но boot-time WFP filters и подтверждение раннего boot protection не реализованы. Не заявляется защита до запуска Windows Base Filtering Engine. Настройки стороннего firewall не сбрасываются; конфликт с другим security software требует отдельного тестирования.

**Аварийное снятие**, только если пользователь действительно хочет разрешить сеть: запустить собственный `foxway-awg.exe guard-off` из полного bundle от администратора. Команда удаляет только известные FoxWay filters, не Windows Firewall целиком. Provider без фильтров может остаться зарегистрированным.

## Linux

Python helper вызывает nft только для `inet foxway_guard`. Output chain покрывает IPv4/IPv6, policy drop. Разрешаются loopback, собственный интерфейс, mark `0x4657` native core и минимальный DHCP/IPv6 neighbor discovery. Нет `ct state established accept`: ранее открытый внешний сокет не получает общего исключения.

VLESS использует `route.default_mark`, AWG получает собственный FwMark. Для TUN используется `fwvless0` либо `fw<hash UID>`. Batch replacement nft атомарен, чужие таблицы не очищаются. Для доступа администратора — pkexec; отсутствие nft/Python/polkit не превращается в «защита включена».

Таблица сохраняется после завершения core/GUI. Восстановление после reboot не заявляется: конфигурация nft не записывается автоматически в системный boot ruleset. Строгая сессия начинается при arm. После аварии app может потребовать явного снятия защиты перед повторным DNS-разрешением новых endpoint hosts.

**Аварийное снятие:** `sudo nft delete table inet foxway_guard`. Только собственная таблица; не `flush ruleset`. Требования: nftables, Python 3, pkexec, /dev/net/tun и зависимости AWG из NATIVE_VPN.md.

## macOS VLESS

PF helper требует root, стандартный единственный filter entry point `com.apple/*` и свой первый child anchor; layout с конкурирующим более ранним anchor или другими main filter rules отклоняется. Это ограничивает совместимость с кастомным PF, зато не выдаёт bypass за работающую защиту; приложение не перезаписывает главный pf.conf. Правила загружаются в `com.apple/000.foxway`, разрешают loopback, `utun88`, точный IP:port endpoint и необходимый control traffic. Разрешающие states для TUN/endpoint привязаны к интерфейсу (`if-bound`).

При активации очищается **таблица текущих соединений PF**: иначе старый floating state способен обойти новые правила. Это закрывает существующие сетевые соединения; действие описано в подтверждении строгого режима. Основные и сторонние firewall rules не удаляются. Действующие сессии других приложений/другого VPN тоже могут прерваться: этот режим рассчитан на один VPN на клиенте.

`pfctl -E` выдаёт собственный reference token, сохраняемый root в `/var/run/foxway-pf.token`. При явном снятии очищается только свой anchor и освобождается собственный token, без общего `pfctl -d`. Система не поддерживается молча, если anchor/права отсутствуют. Это standalone TUN/PF preview, не sandboxed Mac App Store продукт и не signed XPC broker.

**Аварийное восстановление:** открыть FoxWay с теми же необходимыми правами и снять защиту. Ручная администрация должна очистить только `com.apple/000.foxway` и освободить конкретный собственный token; не заменять главный ruleset и не выключать чужие PF references. После reboot PF-защита сессии не обещается.

Обоснование `if-bound`/floating states: [OpenBSD PF options](https://www.openbsd.org/faq/pf/options.html), [pfctl states](https://man.openbsd.org/pfctl). Совместимость конкретной версии macOS PF всё равно требуется проверить на отдельной машине.

## Что реально проверено

Unit/fake-channel тесты policy/удержания guard, safe render nft, Go cross-build Windows и compilation Apple targets проверяют код и сборку. **Ни WFP/nft/PF rules, ни kill core, ни системный lockdown не применялись к компьютеру пользователя.** Для готовности security feature нужен изолированный стенд: живые TCP/UDP до подключения, abrupt core/GUI death, оба IP families/DNS, reconnect/sleep, отказ permissions и конфликт/удаление собственного guard. Без этого не утверждается доказанная защита от утечек на устройствах.

После аварии GUI старый process sing-box может продолжать работу. Снятие firewall само по себе не подтверждает остановку такого orphan core: persistent process registry/supervisor и полное native reconciliation остаются ограничениями preview. Новая instance управляет своим дочерним process; AWG Windows service имеет стабильное собственное имя. До массового выпуска нужны отдельные тесты этого сценария.
