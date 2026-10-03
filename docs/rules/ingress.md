# Ingress: как публиковать сервис

## Короткое правило

**Наружу публикуются только `platform/gateway`, `platform/web` и Keycloak.** Движки (`engines/*`) остаются за `ClusterIP`; их вызывает gateway или другой сервис по имени Service. Ingress у движка включается в `values.yaml` окружения `dev` только для отладки и не попадает в `stage`/`prod`.

## Что используем

Сейчас — **ingress-nginx** (класс `nginx`) с ресурсами `networking.k8s.io/v1 Ingress`. Это то, что уже стоит в кластере и обслуживает GitLab, Argo CD и registry; ресурс Ingress понимают почти все Kubernetes-окружения банков.

**Envoy / Gateway API** — следующий шаг, а не сейчас. Gateway API (`HTTPRoute`) нужен, если банк потребует его или понадобятся трафик-сплит, gRPC без TLS на входе, расширенный роутинг. GitLab chart уже ставит свой Envoy Gateway, но использовать его для Arba не будем, чтобы не смешивать два входа. Когда решим переходить, чарты получат `route.enabled` рядом с `ingress.enabled`, а миграция сводится к замене одного шаблона. Решение фиксируется ADR; до этого `HTTPRoute` в репозиториях не пишем.

## Как писать Ingress

Ingress сам не пишется: его создаёт `.helm/templates/ingress.yaml`, а включается он в `arba/infra`:

```yaml
# envs/dev/gateway/values.yaml
ingress:
  enabled: true
  host: api.dev.arba.kz
```

Правила:

1. `ingressClassName: nginx` всегда явно.
2. Один хост — один сервис. Путь `/`, тип `Prefix`. Пути вида `/<сервис>/` и перезапись путей запрещены: приложения не обязаны жить под префиксом.
3. Имя хоста: `<сервис>.<env>.arba.kz`. Для публичных входов закреплены `api.dev.arba.kz` (gateway), `app.dev.arba.kz` (web), `auth.dev.arba.kz` (Keycloak). Инфраструктура: `gitlab.arba.kz`, `argocd.arba.kz`, `registry.arba.kz`, `grafana.arba.kz`.
4. Разрешённые аннотации: `nginx.ingress.kubernetes.io/proxy-body-size`, `proxy-read-timeout`, `proxy-send-timeout`, `cors-*` (только на gateway). Остальные — через MR с обоснованием.
5. Авторизация — не на уровне Ingress: JWT проверяет gateway и сами движки.
6. Любой публичный эндпоинт идёт через gateway, поэтому лимиты, определение тенанта и аудит не обходятся.

## DNS

Любое имя вида `*.arba.kz` резолвится в `127.0.0.1` на ПК (локальный DNS-контейнер плюс правило Windows) и в ingress-nginx внутри кластера (правило CoreDNS). Поэтому новый хост работает сразу после выкатки; в `hosts` ничего писать не нужно.

## TLS

Сейчас — только http. Блок `ingress.tls` в чарте готов; он включается после установки локального CA (mkcert или cert-manager) вместе с доверием CA в Windows, runner'е и containerd. Для `stage`/`prod` TLS обязателен (NFR-06). Шифровать трафик внутри кластера между сервисами планируется через mTLS (отдельный ADR).

## gRPC

Движки отдают gRPC, gRPC-Web и HTTP/JSON на одном порту (connect-go). Внешним клиентам отдаём HTTP/JSON и gRPC-Web — они проходят через ingress-nginx без особых настроек. Нативный gRPC (`backend-protocol: GRPC`) работает через ingress-nginx только поверх TLS, поэтому для него ждём TLS. Межсервисные вызовы внутри кластера идут напрямую по Service и ingress не используют.

## Локальный gateway (`kuber-gateway`)

Служебный контроллер для разработчика: он сам публикует любой Service и под как `<имя>.arba.kz` (удобно смотреть сервисы в Lens и браузере). Он не заменяет Ingress из чарта и в `stage`/`prod` не ставится. Чтобы не было двойного хоста, чарт ставит на Service аннотацию `kuber-gateway/skip: "true"`, когда `ingress.enabled: true`.
