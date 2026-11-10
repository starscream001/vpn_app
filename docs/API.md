# Действующий бот и v1 API

Приложение 0.3 открывает @Ilyavpnadmin_bot и автоматически обновляет существующие HTTPS-ссылки подписок. Этот путь не требует нового v1 API и не отправляет quality reports сам по себе. [Полная механика](MECHANICS.md). Ниже — отдельный, пока не развёрнутый bearer API/collector.

# Telegram-подписки и отчёты

Никакого bot token и административного VPN-ключа в клиенте. Клиент знает только HTTPS API и короткоживущий bearer token. Текущие бот и серверы не менялись, API в интернет не развёрнут.

## Контракт v1

`POST /v1/auth/exchange`: `{ "code": "one-time-high-entropy-code", "client": "foxway", "version": "0.1.0" }` → `{ "access_token": "opaque", "expires_in": 604800 }`.
Бот после проверки права доступа выдаёт случайный одноразовый код минимум 128 бит, TTL 5 минут, расходование транзакционно. Telegram user ID сам по себе авторизацией не является.

`GET /v1/catalog`, заголовок `Authorization: Bearer ...`:

```json
{"schema":1,"profiles":[{"id":"opaque-profile-id","name":"Нидерланды","protocol":"amnezia","config":"[Interface]\n...","revision":1,"expiresAt":"2027-01-01T00:00:00Z","revoked":false}],"revoked_ids":[]}
```

`protocol`: `amnezia` или `vless`; VLESS config — share URI. Пример config выше является схемой, не рабочим ключом. `expiresAt` обязателен для FoxWay. Идентификатор стабилен между revision, не содержит токен/адрес. Отсутствие в частичном каталоге не равно отзыву: отзыв передавать явно. Backend обязан отзывать ключи и на самих VPN endpoints при завершении доступа — клиентская дата не заменяет серверную авторизацию.

`POST /v1/quality/reports` с bearer:

```json
{"schema":1,"reports":[{"profile_id":"opaque-profile-id","protocol":"amnezia","ok":true,"latency_ms":85,"rx_delta":4321,"tx_delta":512,"reason":"https_204","at":"2026-11-10T00:00:00Z"}]}
```

Ответ `{ "accepted": 1 }`. Только 8 указанных полей; неизвестные поля, чужие profile_id, некорректные типы отклоняются. Пакет 1–20, rate limit 10 пакетов/мин на subject, retention 7 дней в reference API. Реальные интервалы/retention закрепить в политике приватности. У оператора сети/API может быть доступ к source IP на транспортном уровне; reverse-proxy access logs необходимо отключить или минимизировать отдельно.

## Reference API

Python stdlib + SQLite, без сторонних пакетов. Это проверяемый образец интеграции, а не развёрнутый сервис. Локально `python3 backend/service.py` слушает **только 127.0.0.1:8787**, путь БД через `FOXWAY_DB`. Внешний доступ только через TLS reverse proxy, лимит запросов на `/v1/auth/exchange`, лимит body 64 KB, TLS и отдельного сервисного пользователя. Не использовать stdlib HTTP сервер как публичный production ingress.

Доверенный адаптер бота импортирует `Store`, вызывает `provision(subject, catalog)` и `issue_code(subject)` после проверки оплаты. Эти методы намеренно не имеют публичных admin endpoints. SQLite хранит хэши кодов/токенов; каталог с VPN-конфигурациями требует защищённого диска, permissions 0600 и контроля резервных копий. Тесты используют memory DB, без настоящих серверов.

Пока не реализованы: refresh token, привязка лимита устройств, logout/revoke API, серверная выдача AWG/VLESS ключей, webhook оплаты, production deployment. При 401 пользователь заново получает код. Клиент сохраняет expires_in только на уровне серверной проверки токена; плановый refresh отсутствует.

UI входа по коду показывается только при настроенном FOXWAY_API_URL (`--dart-define=FOXWAY_API_URL=https://...`) или уже сохранённой API-привязке. При обычной установке пользователь видит только действующую ссылочную интеграцию бота, без неработающего запроса кода.
