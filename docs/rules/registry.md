# Registry: образы и чарты

Registry работает внутри кластера (namespace `registry`, данные на PVC). Адрес — `registry.arba.kz`, в подах и CI — тот же адрес, с хоста пушить можно как `localhost/<путь>`.

## Что где лежит

| Путь | Что |
| --- | --- |
| `registry.arba.kz/arba/<группа>/<проект>` | образы сервисов, путь = путь проекта в GitLab |
| `registry.arba.kz/arba/charts/<имя>` | Helm-чарты как OCI-артефакты |
| `registry.arba.kz/arba/cache/<проект>` | кэш слоёв Kaniko, можно стирать целиком |
| `registry.arba.kz/base/<имя>` | базовые образы, которые мы закрепили (golang, distroless) — по digest, для воспроизводимости и air-gapped |
| `registry.arba.kz/dev-tmp/*` | личные эксперименты, чистится по расписанию, в `infra` не используется |

## Правила тегов

См. [build.md](build.md): `sha-<коротхеш>` и `X.Y.Z`, `latest` запрещён, теги не перезаписываются. В манифестах окружений образ указывается как `репозиторий:тег@sha256:digest`.

## Как получить доступ

| Откуда | Как |
| --- | --- |
| Поды и Argo CD | образ `registry.arba.kz/...`; containerd на узлах направляет запрос на сервис registry в кластере |
| CI | Kaniko с флагами `--insecure --skip-tls-verify` |
| Хост (Windows) | `docker tag x localhost/arba/x:tag && docker push localhost/arba/x:tag` (Docker считает `localhost` небезопасным реестром сам) |
| Чарты | `helm push chart.tgz oci://registry.arba.kz/arba/charts --plain-http` |

Если Docker Desktop согласен считать `registry.arba.kz` небезопасным (запись `insecure-registries` в настройках Docker Engine), можно пушить и под этим именем.

## Зеркала внешних реестров

В namespace `registry` работают кэширующие зеркала `docker.io`, `registry.gitlab.com`, `quay.io`, `ghcr.io`, `gcr.io`. Узлы кластера ходят в них автоматически: первый раз — наружу, потом из кэша. Kaniko в CI использует зеркало `docker.io` явными флагами (см. [build.md](build.md)). Если зеркало недоступно, containerd идёт напрямую в исходный реестр.

## Хранение и очистка

1. `X.Y.Z` — храним всегда. `sha-*` — последние 30 на проект. `cache/*` и `dev-tmp/*` — можно удалять в любой момент.
2. Удаление в registry:2 не освобождает место само: после удаления манифестов запускается `registry garbage-collect` (CronJob в namespace `registry`, раз в неделю; пока не создан — задача в бэклоге).
3. Образ, на который ссылается `arba/infra` (любое окружение), удалять нельзя — перед очисткой скрипт сверяется с `envs/**`.

## Безопасность

Локальный registry **без авторизации и без TLS**. Это допустимо только на ноутбуке разработчика. Учтите: порты 80/443 кластера kind сейчас открыты на все сетевые интерфейсы ПК, то есть registry виден и из вашей локальной сети; перепривязка к `127.0.0.1` требует пересоздания кластера. Перед использованием за пределами ПК — включить htpasswd или перейти на registry с авторизацией (GitLab Container Registry или Harbor) и TLS; манифесты для этого готовятся вместе с локальным CA.
