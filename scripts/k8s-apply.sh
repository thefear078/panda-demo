#!/usr/bin/env bash
# Опційний шлях: викат у Kubernetes (minikube / kind / будь-який кластер)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

IMAGE_NAME="${IMAGE_NAME:-${DOCKERHUB_USER:-}/panda-web}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo latest)}"

if [[ -z "${IMAGE_NAME}" || "${IMAGE_NAME}" == "/panda-web" ]]; then
  echo "Задай IMAGE_NAME або DOCKERHUB_USER" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "немає kubectl" >&2
  exit 1
fi

FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

# якщо кластер локальний (minikube/kind) — можна зібрати образ і не пушити
if [[ "${BUILD_LOCAL:-0}" == "1" ]]; then
  echo "==> docker build ${FULL_IMAGE}"
  docker build -t "${FULL_IMAGE}" .
  if command -v minikube >/dev/null 2>&1 && minikube status >/dev/null 2>&1; then
    echo "==> load у minikube"
    minikube image load "${FULL_IMAGE}"
  fi
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
cp -r k8s/. "${TMP}/"

# kustomize image rewrite
cat > "${TMP}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: panda-demo
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
images:
  - name: IMAGE_PLACEHOLDER
    newName: ${IMAGE_NAME}
    newTag: ${IMAGE_TAG}
EOF

echo "==> kubectl apply ${FULL_IMAGE}"
kubectl apply -k "${TMP}"

echo "==> rollout"
kubectl -n panda-demo rollout status deployment/panda-web --timeout=120s

echo "==> prune старі ReplicaSet (revisionHistoryLimit уже 3)"
kubectl -n panda-demo get pods,svc

NODE_PORT="$(kubectl -n panda-demo get svc panda-web -o jsonpath='{.spec.ports[0].nodePort}')"
echo "OK: Service NodePort ${NODE_PORT} (мінikube: minikube service panda-web -n panda-demo)"
