# Деплой: GitOps через Argo CD

## Схема

```text
git-тег 1.4.2 (или v1.4.2, fix-infra-merged) на коммите main
  → CI: build (образ <репо>:1.4.2, digest), scan
  → deploy: бот коммитит в argocd/argocd-dev  dev/origination.yml (ревизия, тег, digest)
  → Argo CD (root-dev, app-of-apps) видит изменение
  → рендерит .helm/ репозитория сервиса на этой ревизии
  → применяет в namespace dev
```

Все изменения кластера — коммиты в `argocd/argocd-dev` (окружение dev) и в `arba/infra` (общая платформа: namespace, проекты, правила). Состояние в git = состояние в кластере; Argo CD следит за расхождениями.

## Что лежит в `arba/infra`

```text
infra/
├── argocd/
│   ├── project.yaml            # AppProject arba: какие репозитории и namespace разрешены
│   └── applicationset-dev.yaml # по одному Application на каждую папку envs/dev/*
├── envs/dev/<сервис>/
│   ├── app.yaml                # репозиторий, ревизия, тег, digest (меняет бот)
│   └── values.yaml             # параметры окружения (меняют люди)
├── namespaces/dev.yaml         # namespace, квоты, сетевые политики
├── ci-templates/  templates/  scripts/  releases/  platform/  kind/
```

## Как добавить новый сервис в `dev`

Руками в `argocd-dev` ничего создавать не нужно.

1. В репозитории сервиса есть `.helm/`, `Dockerfile`, `.gitlab-ci.yml` с `SERVICE: <имя>` (см. [helm.md](helm.md), [ci.md](ci.md)).
2. Поставьте git-тег (`0.1.0`, `v0.1.0`). Job `deploy-dev` сам создаст `dev/<имя>.yml` в `argocd/argocd-dev` из шаблона `templates/service.yml.tpl` и пропишет ревизию, тег и digest.
3. Настройки сервиса под dev лежат в **его же репозитории**: необязательный файл `.helm/values-dev.yaml` (переменные, ingress, ресурсы). Общие значения окружения (NATS, JWT) подставляются из `argocd-dev/values/dev-common.yaml`: чарт сам превращает их в `<ИМЯ_СЕРВИСА>_NATS_URL`, `<ИМЯ_СЕРВИСА>_JWT_*`.
4. Нужен PostgreSQL: в `argocd-dev` выполнить `sh scripts/new-database.sh <имя>` (создаёт кластер CloudNativePG и ExternalSecret'ы), запушить, затем `.\19-vault.ps1 -Db <имя>` (пароль в Vault), а в `.helm/values-dev.yaml` сервиса указать `database: { enabled: true }`. DSN попадёт в `<ИМЯ>_DATABASE_DSN` из Secret `<имя>-db`.

## Параметры синхронизации

| Окружение | Синхронизация | Prune | Self-heal |
| --- | --- | --- | --- |
| `dev` | автоматическая | да | да |
| `stage`, `prod` | ручная (кнопка Sync после merge MR) | нет | нет |

## Миграции

Миграции идут Job'ом с хуком `PreSync`: Argo CD сначала выполняет его, и только при успехе обновляет Deployment. Если миграция упала, старая версия продолжает работать. Миграции обратно совместимы (expand → migrate → contract), поэтому откат кода не требует отката схемы.

## Откат

`git revert` коммита в `arba/infra` → merge → Argo CD вернёт прежний digest. Откат правкой в интерфейсе Argo CD работает только до следующей синхронизации. Откат миграции данных делается отдельной миграцией «вперёд».

## Как проверить выкатку

```powershell
# состояние приложений
kubectl -n argocd get applications
# конкретное приложение
kubectl -n argocd get application dev-origination -o jsonpath='{.status.sync.status}{"\t"}{.status.health.status}{"\n"}'
# поды и образ
kubectl -n dev get pods -l app.kubernetes.io/instance=origination -o wide
kubectl -n dev get deploy origination -o jsonpath='{.spec.template.spec.containers[0].image}'
# версия, отданная самим приложением
curl http://origination.dev.arba.kz/version
```

Интерфейс Argo CD — `http://argocd.arba.kz`.

## Диагностика

| Симптом | Куда смотреть |
| --- | --- |
| Application `OutOfSync` и не меняется | у Argo CD нет доступа к репозиторию: проверить Secret-шаблон учётных данных `argocd/repo-creds-arba` |
| `ComparisonError` / не найден чарт | в `app.yaml` неверный `repoURL`, `revision` или `chartPath`; ревизия должна существовать в репозитории сервиса |
| `ImagePullBackOff` | тег и digest из `app.yaml` существуют в registry? `curl http://registry.arba.kz/v2/<путь>/tags/list` |
| Под `Pending` | квота namespace или нехватка памяти на узлах: `kubectl -n dev describe quota` |
| Миграция упала | `kubectl -n dev logs job/<сервис>-migrate-<тег>`; выкатка остановлена до починки |
| `CrashLoopBackOff` | `/readyz` или конфиг: `kubectl -n dev logs <под> --previous` |

## Запрещено

Ручной `kubectl apply/edit/patch` и `helm install` в `dev`; правка `app.yaml` руками (кроме экстренного отката); выкатка образа, которого нет в registry; выкатка в `stage`/`prod` без прохождения `dev`.
