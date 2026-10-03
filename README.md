# arba/infra

Инфраструктура и правила деплоя Arba: GitOps-репозиторий для Argo CD, эталонные шаблоны, общий CI, конфиг kind.

Правила разработки — в [`docs/rules/`](docs/rules/README.md). Начните с него.

| Каталог | Что внутри |
| --- | --- |
| `docs/rules/` | правила: git, go, build, ci, registry, versions, helm, k8s, ingress, deploy, secrets |
| `templates/helm-service/.helm/` | эталонный чарт; копируется в `.helm/` каждого бэкенд-репозитория |
| `templates/go-service/` | `Dockerfile`, `Makefile`, `.gitlab-ci.yml`, `.golangci.yml`, `.go-arch-lint.yml` для нового сервиса |
| `ci-templates/` | общий CI-шаблон `go-engine.yml` (подключается через `include`) |
| `envs/<env>/<сервис>/` | что выкачено в окружении: `app.yaml` (бот), `values.yaml` (люди) |
| `examples/` | образцы, которые не применяются Argo CD |
| `argocd/` | AppProject и ApplicationSet |
| `namespaces/` | namespace `dev`, квоты, сетевые политики |
| `releases/` | манифесты релизов платформы |
| `scripts/` | `bump-env.sh` (бот CI), `render-versions.py` (таблица `VERSIONS.md`) |
| `kind/`, `platform/` | конфиг кластера kind и манифесты платформы (registry) — для воспроизведения стенда |

Стенд поднимают скрипты в `C:\Kuber\k8s` (`go5.ps1`, затем `14-infra.ps1`). Содержимое `envs/` меняется только через MR или бота CI; ручной `kubectl apply` в `dev` запрещён.
