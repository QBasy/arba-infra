# Git: репозитории, ветки, коммиты, релизы

## Репозитории

Структура групп GitLab — как в документе «Arba — подготовка к разработке»: `arba/engines/*` (продаём), `arba/platform/*` (заменяемо), `arba/contracts`, `arba/kit`, `arba/infra`, `arba/docs`. Один репозиторий — один Go-модуль (или одно приложение) — один образ — одна версия по SemVer.

Путь Go-модуля всегда совпадает с путём в GitLab:

```text
module gitlab.arba.kz/arba/engines/origination
```

Новый репозиторий создаётся копированием шаблона из `arba/infra/templates/` (см. [helm.md](helm.md), [build.md](build.md)): `.helm/`, `Dockerfile`, `Makefile`, `.gitlab-ci.yml`, `.golangci.yml`, `.go-arch-lint.yml`, `.tool-versions`, `.dockerignore`.

## Ветки

Trunk-based. Единственная долгоживущая ветка — `main`.

1. Ветка от `main`, живёт не больше 2 дней: `feat/<кратко>`, `fix/<кратко>`, `chore/<кратко>`.
2. Недоделанное прячется за фичефлагом, а не живёт неделями в ветке.
3. Merge только через MR, **squash**, история `main` линейная (merge commit запрещён).
4. `main` защищён: прямой push запрещён (кроме бота для `envs/dev/**` в `arba/infra`), обязателен зелёный пайплайн и минимум один аппрув, для `servicing` и `scoring` — два.

## Коммиты и MR

Conventional Commits, scope — имя сервиса или модуля:

```text
feat(origination): add offer expiry
fix(servicing): round penalty down to tiyn
chore(infra): bump dev origination to sha-1a2b3c4
```

Тип коммита определяет версию: `fix` — patch, `feat` — minor, `feat!` или `BREAKING CHANGE:` — major. MR — не больше 400 строк диффа. Заголовок MR = итоговое сообщение squash-коммита. Ломающее изменение API — только в `/v2` и только после MR с изменением `contracts`.

## Релизы и теги

Каждый merge в `main` собирает образ `sha-<коротхеш>` и сам выкатывается в `dev` — это не релиз. Релиз — аннотированный тег `vMAJOR.MINOR.PATCH` на коммите `main`:

```bash
git tag -a v1.4.2 -m "origination 1.4.2"
git push origin v1.4.2
```

Тег запускает пайплайн релиза: тот же образ получает тег `1.4.2`, публикуется чарт `1.4.2` (см. [ci.md](ci.md), [versions.md](versions.md)). Теги не переносятся и не удаляются.

## Что не коммитим

Секреты, токены, реальные персональные данные, `.env`, `kubeconfig`, бинарники, содержимое `bin/` и `.cache/`. Проверяет `gitleaks` в CI; pre-commit хук `gitleaks protect` ставится командой `make hooks`.
