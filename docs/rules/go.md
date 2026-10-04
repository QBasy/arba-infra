# Go: модуль, версия, зависимости, бинарники

Правила кода (домен, деньги, время, ошибки, идемпотентность, PII) — в документе «Arba — подготовка к разработке», раздел «Строгие правила разработки». Здесь — то, что нужно для сборки и работы в локальной среде.

## Версия Go

Версия задаётся в трёх местах, и они обязаны совпадать по `MAJOR.MINOR`: директива `go` в `go.mod`, `.tool-versions` и переменная `GO_VERSION` в `.gitlab-ci.yml`. Образ сборки берётся как `golang:${GO_VERSION}-alpine`. Шаг `verify` в CI падает, если значения расходятся.

Пример: сейчас в `origination` в `go.mod` стоит `go 1.24.5`, а в Dockerfile — `golang:1.27-alpine`. Выберите одну версию (рекомендую текущую стабильную) и приведите всё к ней.

## Приватные зависимости

Модули `gitlab.arba.kz/...` лежат в локальном GitLab по http, поэтому Go нужны две настройки (скрипт `13-go-modules.ps1` ставит их на вашем ПК):

```bash
go env -w GOINSECURE='*.arba.kz' GOPRIVATE='*.arba.kz'
```

`GOPRIVATE` отключает публичный прокси и базу контрольных сумм для наших модулей. `GOINSECURE` разрешает http. Git должен уметь авторизоваться: токен хранится в Git Credential Manager. В CI это делает `CI_JOB_TOKEN` (см. [ci.md](ci.md)); чтобы он работал, в проектах `contracts` и `kit` в настройках CI/CD → Job token permissions добавьте группу `arba` в список разрешённых.

Зависимости на другие движки запрещены (проверяет `go-arch-lint`). Разрешены `gitlab.arba.kz/arba/contracts` и `gitlab.arba.kz/arba/kit`, версии — только тегами SemVer, не `main`.

## Структура internal/

Одинакова во всех движках, зависимости проверяет `go-arch-lint` (`.go-arch-lint.yml`). Подробная таблица — в «Arba — подготовка к разработке», раздел «Структура репозиториев и движка».

```text
cmd/{server,worker,migrate}   только вызов bootstrap
internal/
  domain/<модуль>/            сущности и правила; stdlib, kit/money, apd
  usecase/                    use cases и порты (интерфейсы объявляет потребитель)
  delivery/httpapi/           хендлеры, ошибки → Problem Details, маппинг DTO
  infrastructure/             postgres, memory, system, клиенты других движков
  bootstrap/                  сборка зависимостей (composition root)
  platform/                   config, buildinfo, testutil
migrations/                   goose, встроены в бинарник
```

Правила: `domain` ни от чего не зависит; `usecase` знает только `domain`; `delivery` и `infrastructure` знают `usecase` и `domain`, но не друг друга; собирает всё `bootstrap`. Общий код между движками живёт в `kit`, а не в `pkg/` движка; `pkg/` заводится только для кода, который осознанно публикуется наружу. Старые имена `app`, `adapters`, `service` не используются.

## Бинарники и образ

Один образ — все `cmd/*`:

| Бинарник | Назначение | Кто запускает |
| --- | --- | --- |
| `/app/server` | gRPC + HTTP/JSON (connect-go), порт 8080 | Deployment |
| `/app/worker` | River-задачи, outbox relay | Deployment `*-worker` (если включён) |
| `/app/migrate` | миграции goose | Job PreSync в Argo CD |

Требования к каждому: конфигурация только через переменные окружения и `/etc/app/config.yaml`; `/healthz` (процесс жив) и `/readyz` (БД и зависимости доступны) на порту server; корректное завершение по `SIGTERM` за ≤ 25 секунд; логи в `stdout` через `slog` в JSON без PII; версия и коммит доступны через `-ldflags` и в `/version`.

## Makefile

Обязательные цели (одинаковые во всех репозиториях, CI вызывает именно их):

| Цель | Что делает |
| --- | --- |
| `make lint` | `golangci-lint`, `go-arch-lint` |
| `make test` | юнит-тесты с `-race` и покрытием |
| `make test-integration` | интеграционные тесты; БД берут из `TEST_DATABASE_URL` |
| `make build` | бинарники в `bin/` |
| `make image` | локальная сборка образа для проверки |
| `make helm-lint` | `helm lint` и `helm template` для `.helm/` |
| `make hooks` | pre-commit: `gitleaks`, `gofmt` |
