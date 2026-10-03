# Kubernetes: правила для сервисов

Кластер — kind `dev` (1 control-plane + 2 worker). Сервисы Arba работают в namespace **`dev`**.

## Namespace'ы

| Namespace | Что там | Кто управляет |
| --- | --- | --- |
| `dev` | всё, что принадлежит Arba: движки, платформа (gateway, web, notifier), зависимости (NATS, MinIO, Keycloak, Gotenberg, Mailpit, моки) | Argo CD из `arba/infra` |
| `gitlab`, `gitlab-runner`, `registry`, `argocd`, `ingress-nginx`, `kuber-gateway` | инфраструктура стенда | скрипты `C:\Kuber\k8s` |
| `observability`, `cert-manager` | появятся по плану спринта 0 | `arba/infra` |

Namespace — это окружение. `stage` и `prod` получат собственные namespace (или кластеры) с теми же манифестами и другими `values.yaml`. Разделение «движок / платформа / зависимость» делается **метками**, а не namespace'ами: `arba.kz/tier: engine | platform | dep`. Изоляцию между ними обеспечивает NetworkPolicy по этим меткам.

Namespace `dev` создаётся манифестом `arba/infra/namespaces/dev.yaml`: сам namespace, `ResourceQuota`, `LimitRange` и сетевые политики по умолчанию. Руками в нём ничего не создаётся.

## Обязательные метки

| Метка | Значение |
| --- | --- |
| `app.kubernetes.io/name` | имя сервиса |
| `app.kubernetes.io/instance` | имя релиза (= имя сервиса) |
| `app.kubernetes.io/version` | версия образа |
| `app.kubernetes.io/part-of` | `arba` |
| `arba.kz/tier` | `engine`, `platform` или `dep` |
| `arba.kz/env` | `dev`, `stage`, `prod` |
| `arba.kz/process` | `server`, `worker`, `migrate` (на подах) |

Чарт из шаблона ставит их сам.

## Ресурсы

1. У каждого контейнера есть `requests` и `limits.memory`. **CPU limit не ставим**: он вызывает троттлинг без пользы. Память всегда ограничена — Go получает `GOMEMLIMIT` из лимита (чарт делает это сам).
2. Значения по умолчанию для dev: `requests: 50m / 64Mi`, `limits.memory: 256Mi`. Завышенные requests запрещены: узлы используют общие ~30 ГБ вместе с GitLab, Keycloak и наблюдаемостью.
3. `ResourceQuota` в `dev`: до 8 CPU и 12 ГиБ памяти по requests. Не помещаетесь — оптимизируйте, а не просите увеличить.
4. Реплик: `dev` — 1, `stage` и `prod` — минимум 2 (NFR-01), с PodDisruptionBudget (чарт включает его при репликах > 1).

## Пробы и жизненный цикл

`/healthz` — процесс жив (liveness); `/readyz` — готов принимать трафик (readiness): БД и обязательные зависимости доступны. Нельзя использовать зависимости в liveness: перезапуск пода не чинит упавшую БД. Завершение по `SIGTERM` за ≤ 25 секунд; `terminationGracePeriodSeconds` — 30. Обновление — `RollingUpdate` с `maxUnavailable: 0`.

## Безопасность подов

Чарт задаёт: `runAsNonRoot`, UID/GID 65532, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`. Запись — только в `/tmp` (`emptyDir`). Привилегированные поды, `hostPath`, `hostNetwork` запрещены. Выкладывать от root можно только инфраструктурным компонентам, и это фиксируется ADR.

## Конфигурация и секреты

Конфиг — `config:` (ConfigMap) и `env:`. Секреты — только `Secret`, подключаемый через `secretEnv` или `envFromSecrets`; в `values.yaml`, образах и git их нет (см. [secrets.md](secrets.md)). Конфигурацию правил регулятора (предельная ГЭСВ, форма договора) держим в конфиге тенанта, не в коде.

## Сеть

1. Внутри кластера сервисы обращаются друг к другу по имени Service: `http://scoring:8080` в том же namespace, `http://scoring.dev.svc.cluster.local:8080` из другого.
2. В `dev` действует политика «запретить входящий трафик по умолчанию»; сервис получает разрешение от своего чарта (`networkPolicy.ingressFrom`). Движки не принимают трафик от `platform` напрямую, кроме `gateway`.
3. Исходящий трафик в `dev` пока открыт; в `stage`/`prod` — закрывается явным списком.
4. Публиковать наружу — только через [ingress.md](ingress.md).
5. Проверка, что политики реально действуют, обязательна: kindnet в свежем kind умеет NetworkPolicy, но убедитесь тестом (под из другого namespace не должен достучаться до движка).

## База данных

Каждый движок имеет собственный кластер PostgreSQL (оператор CloudNativePG, ставится в спринте 0) с именем `<движок>-db` в том же namespace. Приложение получает строку подключения из Secret `<движок>-db-app` (ключ `uri`) через `secretEnv`. Движки не читают чужие БД. Схемы — по модулям (`origination.*`), миграции goose, только вперёд и обратно совместимые.

## Именование

Сервис = имя репозитория = имя релиза Argo CD = имя Deployment = имя Service. Hostname — `<сервис>.<env>.arba.kz`. Secret'ы: `<сервис>-<назначение>` (`origination-db-app`, `gateway-oidc`).

## Что нельзя

`kubectl apply/edit/patch` в `dev` руками (self-heal откатит, а следы не останутся в git); `latest` и теги без digest в манифестах; `NodePort` и `LoadBalancer` у сервисов Arba; общий PVC между сервисами; запуск `Job` с образом, которого нет в `arba/infra`.

Для диагностики `kubectl get/describe/logs/exec/port-forward` разрешены, как и `kubectl debug`.
