#!/usr/bin/env bash
# Build the custom Spark image and load it into the local Kind cluster so
# kubelet can pull it with imagePullPolicy: IfNotPresent (no registry needed).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE="${SPARK_IMAGE:-iceberg-spark:3.5.6}"
KIND_CLUSTER="${KIND_CLUSTER_NAME:-iceberg}"
PLATFORM="${BUILD_PLATFORM:-}"

echo "==> Building ${IMAGE}"
if [[ -n "${PLATFORM}" ]]; then
  docker buildx build --platform "${PLATFORM}" --load -t "${IMAGE}" "${SCRIPT_DIR}"
else
  docker build -t "${IMAGE}" "${SCRIPT_DIR}"
fi

if kind get clusters 2>/dev/null | grep -qx "${KIND_CLUSTER}"; then
  echo "==> Loading ${IMAGE} into kind cluster ${KIND_CLUSTER}"
  kind load docker-image "${IMAGE}" --name "${KIND_CLUSTER}"
else
  echo "Kind cluster '${KIND_CLUSTER}' not found; skipping kind load." >&2
fi

echo "Done."
