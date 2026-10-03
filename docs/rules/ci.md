# CI: пайплайн и правила

Каждый репозиторий сервиса подключает общий шаблон из `arba/infra`, свой `.gitlab-ci.yml` — пять строк:

```yaml
include:
  - project: arba/infra
    ref: main
    file: ci-templates/go-engine.yml
variables:
  GO_VERSION: "1.27"
  SERVICE: origination
```

Шаблон меняется только через MR в `arba/infra`. Копировать его в репозиторий сервиса нельзя.

## Стадии

| Стадия | Задачи | Когда | Блокирует merge |
| --- | --- | --- | --- |
| `verify` | `go mod tidy` без диффа, согласованность версий Go, `golangci-lint`, `go-arch-lint`, `helm lint` + `helm template` для `.helm/`, `gitleaks` | MR и `main` | да |
| `test` | юнит-тесты с `-race`, интеграционные тесты, порог покрытия | MR и `main` | да |
| `build` | сборка образа Kaniko, push `sha-<коротхеш>`, запись digest | `main` | — |
| `scan` | `govulncheck`, `trivy` по образу, SBOM | `main` | см. ниже |
| `deploy` | бот меняет `envs/dev/<сервис>/app.yaml` в `arba/infra` | `main` | — |
| `release` | перетегирование образа на `X.Y.Z`, публикация чарта в OCI | тег `vX.Y.Z` | — |

Пайплайн на теге не пересобирает образ: берёт образ коммита, который уже прошёл `main`.

## Интеграционные тесты

В Kubernetes-раннере нет Docker-демона, поэтому `testcontainers-go` в CI не работает. Интеграционные тесты читают подключение из `TEST_DATABASE_URL`; в CI его предоставляет сервис пайплайна (`postgres:17`), локально — любой PostgreSQL или `testcontainers`. Тест, который запускает контейнеры сам, помечается тегом сборки `//go:build testcontainers` и в CI не идёт.

## Покрытие

Порог `COVERAGE_MIN` (по умолчанию 75 для всего кода), для пакета `domain` — 90 (проверяется отдельной командой в шаблоне). Снижать порог можно только через ADR.

## Токены и доступы

| Что | Как | Где хранится |
| --- | --- | --- |
| Скачать приватные модули при сборке | `CI_JOB_TOKEN`; группа `arba` добавлена в Job token permissions проектов `contracts` и `kit` | выдаёт GitLab |
| Запушить образ | registry локальный и без авторизации (только `dev`) | — |
| Обновить `arba/infra` | `INFRA_PUSH_TOKEN` — токен проекта `arba/infra` с правом `write_repository` | переменная CI на уровне группы `arba`, masked, protected |
| Argo CD читает репозитории | групповой deploy token `argocd` (`read_repository`) | Secret в namespace `argocd` |

`INFRA_PUSH_TOKEN` и deploy token создаёт скрипт `14-infra.ps1`; значения не коммитятся и не печатаются в логи.

## Runner

Один групповой runner `local-k8s` (executor `kubernetes`, namespace `gitlab-runner`), задачи идут подами без привилегий. Образ задачи всегда с явной версией (`golang:1.27`, а не `golang`). Задачи, которым нужен Docker-демон, не пишем: для сборки есть Kaniko, для тестов — сервисы пайплайна.

## Известные ограничения

Образы сканеров и их базы скачиваются из интернета; пока локального зеркала нет, задача `scan` идёт с `allow_failure: true` и печатает предупреждение. После появления зеркала флаг убираем. Версии образов линтеров и сканеров в шаблоне указаны переменными в начале файла — при первом запуске проверьте, что такие теги существуют, и поправьте в одном месте.
