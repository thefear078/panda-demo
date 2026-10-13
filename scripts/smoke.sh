#!/usr/bin/env bash
# Швидка перевірка після docker compose up
set -euo pipefail

PORT="${HOST_PORT:-80}"
BASE="http://127.0.0.1:${PORT}"

echo "GET ${BASE}/health"
curl -fsS "${BASE}/health"
echo

echo "GET ${BASE}/"
code="$(curl -s -o /dev/null -w '%{http_code}' "${BASE}/")"
[[ "${code}" == "200" ]] || { echo "очікував 200, отримав ${code}" >&2; exit 1; }
echo "index OK (${code})"

if command -v docker >/dev/null 2>&1; then
  echo "compose health:"
  docker inspect -f '{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' panda-web panda-autoheal 2>/dev/null || true
fi
