# Сборка образов

Один репозиторий — один образ со всеми бинарниками `cmd/*`. Образ собирает CI (стадия `build`), локально — `make image` только для проверки. Образы, собранные на ноутбуке, в registry не пушим.

## Dockerfile

Эталон — `arba/infra/templates/go-service/Dockerfile`. Правила:

1. Два этапа: сборка на `golang:${GO_VERSION}-alpine`, итог на `gcr.io/distroless/static-debian12:nonroot`. В итоговом образе нет оболочки, пакетного менеджера и root.
2. `CGO_ENABLED=0`, флаги `-trimpath -ldflags "-s -w -X …"`. Сборка воспроизводима: одинаковый коммит даёт одинаковый бинарник.
3. Сначала копируем `go.mod` и `go.sum`, скачиваем зависимости, потом копируем код — так слой с зависимостями кэшируется.
4. Версия базового образа задаётся аргументом `GO_VERSION`, равным версии в `go.mod` (см. [go.md](go.md)). Теги вида `latest` и `alpine` без версии запрещены.
5. Образ запускается от `65532:65532`, корневая файловая система только для чтения; временные файлы — в `/tmp` (в Kubernetes туда монтируется `emptyDir`).
6. Приватные модули: токен передаётся аргументом `GIT_TOKEN` **только в этапе сборки**, пишется в git-конфиг и стирается в той же команде `RUN`, чтобы не попасть в слой. Секреты в `ENV` и `COPY` запрещены.
7. Метки OCI в итоговом образе: `org.opencontainers.image.source`, `.revision`, `.version`, `.created` — их ставит CI через `--label`.

## Теги образов

Имя: `registry.arba.kz/<путь-в-GitLab>`, например `registry.arba.kz/arba/engines/origination`.

| Тег | Когда появляется | Меняется ли |
| --- | --- | --- |
| `1.4.2` / `v1.4.2` | git-тег с таким именем; образ собирается на тег, **тег образа = имя git-тега** | никогда |
| `fix-infra-merged` | особая версия: любой другой git-тег (буквы, цифры, `.`, `_`, `-`) | никогда |
| `1.4` / `1` | не используем | — |
| `latest`, `main`, `sha-*` | не создаются: образ без git-тега не собирается | — |

Образ собирается **только по git-тегу**. Коммиты в `main` и MR образ не собирают, только проверяют код. Новый образ — новый тег; существующий тег не переносится.
Тег — удобное имя для человека. Идентификатор образа — **digest** (`sha256:…`): он записывается в `arba/infra` и по нему идёт деплой. Если кто-то перепушит тег, развёрнутое не изменится.

## Как собирает CI

Шаблон `ci-templates/go-engine.yml` запускает Kaniko без привилегий и без Docker:

```text
/kaniko/executor --context . --dockerfile Dockerfile
  --destination registry.arba.kz/<путь>:<git-тег>
  --digest-file /tmp/digest
  --cache=true --cache-repo=registry.arba.kz/arba/cache/<проект>
  --build-arg GO_VERSION --build-arg VERSION --build-arg COMMIT --build-arg MODULE --build-arg GIT_TOKEN
  --insecure --skip-tls-verify
  --registry-mirror=mirror-docker.registry.svc.cluster.local:5000
  --insecure-registry=mirror-docker.registry.svc.cluster.local:5000
```

`--insecure` нужен, потому что registry пока работает по http. Digest записывается в артефакт `build.env` и дальше уходит в `deploy`. Выкатить можно только образ, собранный по git-тегу.

## Версия внутри бинарника

Версия и коммит попадают в `internal/platform/buildinfo` через `-ldflags` и отдаются на `/version`. `VERSION` равна git-тегу (`1.4.2`, `fix-infra-merged`). Так по запущенному поду всегда видно, из какого коммита он собран.

## Локальная проверка

```powershell
make image            # собирает образ локальным docker, тег arba-local/<сервис>:dev
make helm-lint        # проверяет .helm
```

Чтобы быстро проверить образ в кластере без CI, пушить можно только в отдельный путь `registry.arba.kz/dev-tmp/<имя>`, он чистится по расписанию и не используется в `arba/infra`.

## Что нельзя

Собирать образ из грязного рабочего дерева для `dev`/`stage`/`prod`; пушить тег `latest`; пушить образ без пайплайна; хранить в образе конфиги окружений и секреты; ставить в итоговый образ утилиты «для отладки» (для этого есть `kubectl debug` с эфемерным контейнером).
