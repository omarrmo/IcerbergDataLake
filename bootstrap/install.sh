#!/usr/bin/env bash
# Bootstrap layer: installs the cluster-wide infrastructure that Argo CD itself
# depends on (ingress-nginx) and Argo CD itself. After this runs successfully,
# `kubectl apply -f platform/apps/root.yaml` hands control to Argo CD.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

INGRESS_NGINX_VERSION="${INGRESS_NGINX_VERSION:-4.11.3}"
ARGOCD_VERSION="${ARGOCD_VERSION:-7.7.5}"

ensure_repo() {
  local name="$1" url="$2"
  helm repo list 2>/dev/null | awk '{print $1}' | grep -qx "$name" || helm repo add "$name" "$url"
}

echo "==> Adding Helm repos"
ensure_repo ingress-nginx https://kubernetes.github.io/ingress-nginx
ensure_repo argo https://argoproj.github.io/argo-helm
helm repo update >/dev/null

echo "==> Installing ingress-nginx (namespace: ingress-nginx)"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --version "${INGRESS_NGINX_VERSION}" \
  --values "${SCRIPT_DIR}/ingress-nginx/values.yaml" \
  --wait --timeout 5m

echo "==> Installing Argo CD (namespace: argocd)"
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version "${ARGOCD_VERSION}" \
  --values "${SCRIPT_DIR}/argocd/values.yaml" \
  --wait --timeout 10m

echo "==> Waiting for Argo CD CRDs"
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m

echo
echo "Bootstrap complete."
echo "  Argo CD UI: http://argocd.localtest.me"
echo "  Initial admin password:"
echo "    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
