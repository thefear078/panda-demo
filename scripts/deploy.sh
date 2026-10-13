#!/usr/bin/env bash
# build → push → deploy по SSH → health → prune
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

IMAGE_NAME="${IMAGE_NAME:-${DOCKERHUB_USER:-}/panda-web}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo latest)}"
HOST_PORT="${HOST_PORT:-80}"
DEPLOY_HOST="${DEPLOY_HOST:-}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/panda-demo}"
SKIP_PUSH="${SKIP_PUSH:-0}"
SKIP_DEPLOY="${SKIP_DEPLOY:-0}"

if [[ -z "${IMAGE_NAME}" || "${IMAGE_NAME}" == "/panda-web" ]]; then
  echo "Задай IMAGE_NAME або DOCKERHUB_USER (напр. myuser/panda-web)" >&2
  exit 1
fi

FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
LATEST_IMAGE="${IMAGE_NAME}:latest"

echo "==> build ${FULL_IMAGE}"
docker build -t "${FULL_IMAGE}" -t "${LATEST_IMAGE}" .

if [[ "${SKIP_PUSH}" != "1" ]]; then
  if [[ -n "${DOCKERHUB_TOKEN:-}" && -n "${DOCKERHUB_USER:-}" ]]; then
    echo "==> login docker hub"
    echo "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USER}" --password-stdin
  fi
  echo "==> push ${FULL_IMAGE}"
  docker push "${FULL_IMAGE}"
  docker push "${LATEST_IMAGE}"
else
  echo "==> skip push"
fi

if [[ "${SKIP_DEPLOY}" == "1" ]]; then
  echo "==> skip deploy"
  exit 0
fi

if [[ -z "${DEPLOY_HOST}" ]]; then
  echo "DEPLOY_HOST порожній — образ зібрано, на сервер не катаю" >&2
  exit 0
fi

echo "==> sync compose на ${DEPLOY_HOST}:${DEPLOY_PATH}"
ssh -o StrictHostKeyChecking=accept-new "${DEPLOY_HOST}" "mkdir -p '${DEPLOY_PATH}'"
scp -q docker-compose.yml "${DEPLOY_HOST}:${DEPLOY_PATH}/docker-compose.yml"

ssh "${DEPLOY_HOST}" "cat > '${DEPLOY_PATH}/.env' <<EOF
IMAGE_NAME=${IMAGE_NAME}
IMAGE_TAG=${IMAGE_TAG}
HOST_PORT=${HOST_PORT}
EOF"

echo "==> pull + up (чекаємо healthy)"
ssh "${DEPLOY_HOST}" \
  "cd '${DEPLOY_PATH}' && docker compose pull && docker compose up -d --remove-orphans --wait --wait-timeout 90"

echo "==> health HTTP"
if ssh "${DEPLOY_HOST}" "curl -fsS \"http://127.0.0.1:${HOST_PORT}/health\""; then
  echo
else
  echo "health check не пройшов" >&2
  ssh "${DEPLOY_HOST}" "cd '${DEPLOY_PATH}' && docker compose ps && docker compose logs --tail=80" || true
  exit 1
fi

echo "==> cleanup на сервері (dangling images/containers)"
ssh "${DEPLOY_HOST}" \
  "docker image prune -f >/dev/null; docker container prune -f >/dev/null; \
   docker images '${IMAGE_NAME}' --format '{{.Repository}}:{{.Tag}}' \
   | grep -v ':latest\$' | grep -v ':${IMAGE_TAG}\$' | tail -n +4 \
   | xargs -r docker rmi 2>/dev/null || true"

echo "OK: ${FULL_IMAGE} на ${DEPLOY_HOST} :${HOST_PORT}"
