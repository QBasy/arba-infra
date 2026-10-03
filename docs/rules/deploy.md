# Деплой: GitOps через Argo CD

## Схема

```text
merge в main (arba/engines/origination)
  → CI: verify, test, build (образ sha-1a2b3c4, digest), scan
  → deploy: бот коммитит в arba/infra  envs/dev/origination/app.yaml
  → Argo CD (ApplicationSet) видит изменение
  → рендерит .helm/ репозитория сервиса на нужной ревизии + values.yaml из infra
  → применяет в namespace dev
```

Все изменения кластера — коммиты в `arba/infra`. Состояние в git = состояние в кластере; Argo CD следит за расхождениями.

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

1. В репозитории сервиса есть `.helm/`, `Dockerfile`, `.gitlab-ci.yml` (см. [helm.md](helm.md), [ci.md](ci.md)). После merge в `main` образ собран.
2. В `arba/infra` создайте `envs/dev/<сервис>/app.yaml` (образец — `examples/envs/dev/origination/`; поменяйте `name` и `repoURL`) и пустой `values.yaml`.
3. Merge MR. ApplicationSet создаст Application, Argo CD выкатит сервис; дальше обновлять `app.yaml` будет бот.

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
