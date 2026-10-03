# Helm: правило `.helm`

**В каждом бэкенд-репозитории лежит каталог `.helm/` с чартом этого сервиса.** Чарт живёт рядом с кодом: изменение кода, требующее новой переменной окружения, порта или пробы, идёт одним MR вместе с изменением чарта. Это заменяет путь `deploy/helm/<имя>/` из документа «Arba — подготовка к разработке».

## Структура

Эталон — `arba/infra/templates/helm-service/.helm/`. Копируется в репозиторий целиком:

```text
.helm/
├── Chart.yaml            # name = имя репозитория; version/appVersion подставляет CI
├── values.yaml           # значения по умолчанию, пригодные для dev
└── templates/
    ├── _helpers.tpl
    ├── deployment.yaml   # процесс server
    ├── worker.yaml       # процесс worker (включается worker.enabled)
    ├── migrate-job.yaml  # миграции перед выкаткой (migrate.enabled)
    ├── service.yaml
    ├── ingress.yaml      # выключен по умолчанию, см. ingress.md
    ├── configmap.yaml
    ├── serviceaccount.yaml
    ├── pdb.yaml
    └── networkpolicy.yaml
```

Менять структуру можно: добавлять шаблоны (например, `ServiceMonitor`, CronJob). Нельзя убирать то, что обеспечивает безопасность и пробы (securityContext, probes, requests/limits, labels). Изменения эталона делаются в `arba/infra/templates/` и раскатываются MR во все репозитории.

## Что хранится где

| Что | Где |
| --- | --- |
| Структура ресурсов, пробы, securityContext, метки, значения по умолчанию | `.helm/` в репозитории сервиса |
| Тег и digest образа, ревизия чарта | `arba/infra` → `envs/<env>/<сервис>/app.yaml` (бот) |
| Реплики, хосты, ресурсы, включение worker/migrate, конфиг приложения для окружения | `arba/infra` → `envs/<env>/<сервис>/values.yaml` (люди) |
| Секреты | не в git, см. [secrets.md](secrets.md) |

В `.helm/values.yaml` **нет** значений, зависящих от окружения (хосты, пароли, адреса соседних сервисов в `dev`/`prod`). Они приходят из `arba/infra`.

## Соглашения

1. Имена ресурсов равны имени релиза Argo CD (`origination`, `scoring`), поэтому внутри namespace имя сервиса = имя Service: `http://scoring:8080`.
2. Образ собирается из `image.repository`, `image.tag` и `image.digest` — формат `репо:тег@sha256:…`. Для чарта без digest (локальная проверка) допустим один тег.
3. Порт HTTP — `8080` (connect-go: gRPC, gRPC-Web, HTTP/JSON на одном порту). Пробы: `/healthz` и `/readyz`.
4. Миграции — отдельный Job с аннотациями Argo CD `PreSync` и Helm `pre-upgrade`; приложение стартует только после успешной миграции.
5. `automountServiceAccountToken: false`, если сервису не нужен API Kubernetes.
6. Конфигурация приложения — `config:` (попадает в ConfigMap и монтируется в `/etc/app/config.yaml`; смена значения перезапускает поды через checksum), переменные — `env:`, секреты — `secretEnv:` или `envFromSecrets:`.

## Проверка

```powershell
make helm-lint
# то же самое вручную:
helm lint .helm --set image.tag=0.0.0
helm template origination .helm --set image.tag=0.0.0 --set worker.enabled=true --set migrate.enabled=true
```

`helm lint` и `helm template` входят в стадию `verify` в CI. Рекомендуется добавить `kubeconform` для проверки схем.

## Публикация чарта

В dev Argo CD берёт `.helm/` прямо из git по ревизии из `app.yaml`. Для поставки банку и umbrella-чарта на теге `vX.Y.Z` CI дополнительно упаковывает чарт и публикует его как OCI-артефакт:

```bash
helm package .helm --version 1.4.2 --app-version 1.4.2
helm push origination-1.4.2.tgz oci://registry.arba.kz/arba/charts --plain-http
```
