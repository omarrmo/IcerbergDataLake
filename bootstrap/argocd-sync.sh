#!/usr/bin/env bash
# Render bootstrap/argocd/root-app.yaml with REPO_URL + TARGET_REVISION and
# apply it. Argo CD then takes over and reconciles platform/apps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${REPO_URL:?REPO_URL must be set, e.g. https://github.com/<you>/IcerbergDataLake.git}"
: "${TARGET_REVISION:=main}"

export REPO_URL TARGET_REVISION

if ! command -v envsubst >/dev/null 2>&1; then
  echo "envsubst not found; install gettext (brew install gettext)." >&2
  exit 1
fi

envsubst '${REPO_URL} ${TARGET_REVISION}' \
  < "${SCRIPT_DIR}/argocd/root-app.yaml" \
  | kubectl apply -f -

echo
echo "Root Application applied. Watch Argo CD reconcile:"
echo "  kubectl -n argocd get applications -w"
