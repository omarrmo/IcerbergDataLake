#!/usr/bin/env bash
# Create all platform Secrets in the cluster from gitignored .env files.
# Idempotent: re-running replaces the Secret in place.
set -euo pipefail

NAMESPACE="${NAMESPACE:-mlops}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "ERROR: $1 not found." >&2
    echo "       cp $1.example $1   and fill in the values." >&2
    exit 1
  fi
}

ensure_namespace() {
  kubectl get namespace "$1" >/dev/null 2>&1 || kubectl create namespace "$1"
}

create_secret_from_env() {
  local ns="$1"
  local name="$2"
  local file="$3"
  ensure_namespace "$ns"
  kubectl -n "$ns" create secret generic "$name" \
    --from-env-file="$file" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# AWS creds for Spark driver/executors and Trino
AWS_FILE="${SCRIPT_DIR}/aws-creds.env"
require_file "$AWS_FILE"
create_secret_from_env "$NAMESPACE" aws-creds "$AWS_FILE"
echo "Created secret ${NAMESPACE}/aws-creds"

# Grafana admin (only if file exists; optional in minimal setups)
GRAFANA_FILE="${SCRIPT_DIR}/grafana-admin.env"
if [[ -f "$GRAFANA_FILE" ]]; then
  create_secret_from_env "$MONITORING_NAMESPACE" grafana-admin "$GRAFANA_FILE"
  echo "Created secret ${MONITORING_NAMESPACE}/grafana-admin"
fi
