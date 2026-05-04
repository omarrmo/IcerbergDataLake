#!/usr/bin/env bash
# End-to-end smoke test:
#   1. Apply the demo SparkApplication into mlops (out-of-band of Airflow).
#   2. Wait for it to reach COMPLETED.
#   3. Run a Trino SELECT against the same Iceberg table via the Nessie catalog.
#
# Idempotent: safe to run multiple times.
set -euo pipefail

NAMESPACE="${NAMESPACE:-mlops}"
SPARKAPP_NAME="${SPARKAPP_NAME:-iceberg-write-demo}"
SPARKAPP_FILE="${SPARKAPP_FILE:-jobs/iceberg-write/sparkapplication.yaml}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
TRINO_HOST="${TRINO_HOST:-trino.localtest.me}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Ensuring the iceberg-demo-app ConfigMap exists (kustomize build)"
kubectl apply -k "${REPO_ROOT}/jobs/iceberg-write"

echo "==> Submitting SparkApplication ${SPARKAPP_NAME}"
kubectl -n "${NAMESPACE}" delete sparkapplication "${SPARKAPP_NAME}" --ignore-not-found
kubectl -n "${NAMESPACE}" apply -f "${REPO_ROOT}/${SPARKAPP_FILE}"

echo "==> Waiting up to ${TIMEOUT_SECONDS}s for SparkApplication to complete"
deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while :; do
  state=$(kubectl -n "${NAMESPACE}" get sparkapplication "${SPARKAPP_NAME}" \
    -o jsonpath='{.status.applicationState.state}' 2>/dev/null || echo "")
  case "$state" in
    COMPLETED) echo "  -> COMPLETED"; break ;;
    FAILED|FAILING|UNKNOWN)
      echo "  -> ${state}"
      kubectl -n "${NAMESPACE}" describe sparkapplication "${SPARKAPP_NAME}" || true
      kubectl -n "${NAMESPACE}" logs -l spark-role=driver --tail=200 || true
      exit 1
      ;;
    *) echo "  state=${state:-<pending>}"; sleep 10 ;;
  esac
  if (( $(date +%s) >= deadline )); then
    echo "Timed out waiting for ${SPARKAPP_NAME}." >&2
    exit 1
  fi
done

echo
echo "==> Driver logs (tail)"
kubectl -n "${NAMESPACE}" logs -l spark-role=driver --tail=40 || true

echo
echo "==> Querying Trino via ingress at http://${TRINO_HOST}"
if ! command -v trino >/dev/null 2>&1; then
  echo "  trino CLI not installed locally; skipping read verification." >&2
  echo "  install:  brew install trino  or  https://trino.io/download"
  exit 0
fi

trino --server "http://${TRINO_HOST}" --catalog iceberg --schema demo \
  --execute "SELECT * FROM hello ORDER BY id"

echo
echo "Smoke test PASSED."
