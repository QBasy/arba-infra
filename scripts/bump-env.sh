#!/bin/sh
# Обновляет envs/<env>/<service>/app.yaml (ревизия, тег, digest) и коммитит в arba/infra.
# Вызывается ботом CI; можно запускать и вручную для экстренного отката.
# Использование: bump-env.sh --infra DIR --env dev --service origination --repo URL --revision SHA --tag sha-1a2b3c4 --digest sha256:... [--push]
set -eu
PUSH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --infra) INFRA=$2; shift 2;;
    --env) ENVN=$2; shift 2;;
    --service) SERVICE=$2; shift 2;;
    --repo) REPO=$2; shift 2;;
    --revision) REVISION=$2; shift 2;;
    --tag) TAG=$2; shift 2;;
    --digest) DIGEST=$2; shift 2;;
    --push) PUSH=1; shift;;
    *) echo "unknown arg $1" >&2; exit 2;;
  esac
done
: "${INFRA:?}" "${ENVN:?}" "${SERVICE:?}" "${REVISION:?}" "${TAG:?}" "${DIGEST:?}"
case "$DIGEST" in sha256:*) ;; *) echo "digest must start with sha256:" >&2; exit 2;; esac
DIR="$INFRA/envs/$ENVN/$SERVICE"
FILE="$DIR/app.yaml"
mkdir -p "$DIR"
if [ ! -f "$FILE" ]; then
  : "${REPO:?--repo is required for a new service}"
  cat > "$FILE" <<YAML
# Поля revision, imageTag, imageDigest обновляет бот CI (scripts/bump-env.sh). Остальное — люди.
name: $SERVICE
namespace: $ENVN
repoURL: $REPO
chartPath: .helm
revision: "$REVISION"
imageTag: "$TAG"
imageDigest: "$DIGEST"
YAML
  [ -f "$DIR/values.yaml" ] || printf '# Параметры окружения %s для %s (люди)\n' "$ENVN" "$SERVICE" > "$DIR/values.yaml"
else
  sed -i -e "s|^revision:.*|revision: \"$REVISION\"|" \
         -e "s|^imageTag:.*|imageTag: \"$TAG\"|" \
         -e "s|^imageDigest:.*|imageDigest: \"$DIGEST\"|" "$FILE"
fi
cd "$INFRA"
# справочная таблица версий (если в окружении есть python3 + pyyaml)
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  python3 scripts/render-versions.py >/dev/null && git add VERSIONS.md
fi
git add "envs/$ENVN/$SERVICE"
if git diff --cached --quiet; then echo "nothing to change"; exit 0; fi
git -c user.name="infra-bot" -c user.email="infra-bot@arba.kz" commit -q -m "chore($ENVN): $SERVICE -> $TAG"
if [ "$PUSH" = 1 ]; then
  for i in 1 2 3; do
    git push -q origin HEAD:main && exit 0
    git pull -q --rebase origin main
  done
  echo "push failed" >&2; exit 1
fi
