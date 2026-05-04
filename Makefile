SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Load .env if present (used for KIND_CLUSTER_NAME, REPO_URL, INGRESS_DOMAIN, ...).
ifneq ($(wildcard .env),)
include .env
export
endif

KIND_CLUSTER_NAME ?= iceberg
SPARK_IMAGE       ?= iceberg-spark:3.5.6
TARGET_REVISION   ?= main
INGRESS_DOMAIN    ?= localtest.me

# REPO_URL must be set: it's where Argo CD pulls platform/, dags/, jobs/ from.
# For local dev, push this repo to your fork and set REPO_URL=https://github.com/<you>/IcerbergDataLake.git
REPO_URL ?=

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

##@ Help
.PHONY: help
help: ## Print this help
	@awk 'BEGIN{FS=":.*##"; printf "\nUsage:\n  make <target>\n\nTargets:\n"} \
	  /^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2} \
	  /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)}' $(MAKEFILE_LIST)

##@ Cluster lifecycle
.PHONY: kind-up
kind-up: ## Create the Kind cluster
	kind create cluster --name $(KIND_CLUSTER_NAME) --config $(ROOT_DIR)/cluster/kind.yaml || true
	kubectl cluster-info --context kind-$(KIND_CLUSTER_NAME)

.PHONY: kind-down
kind-down: ## Delete the Kind cluster
	kind delete cluster --name $(KIND_CLUSTER_NAME)

.PHONY: bootstrap
bootstrap: ## Install ingress-nginx + Argo CD (cluster must already exist)
	bash $(ROOT_DIR)/bootstrap/install.sh

.PHONY: image
image: ## Build the custom Spark image and load it into Kind
	SPARK_IMAGE=$(SPARK_IMAGE) KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) \
	  bash $(ROOT_DIR)/images/spark/build.sh

.PHONY: secrets
secrets: ## Create aws-creds (and grafana-admin if present) from secrets/*.env
	bash $(ROOT_DIR)/secrets/create.sh

.PHONY: argocd-sync
argocd-sync: ## Apply the root Argo Application (requires REPO_URL)
	@if [ -z "$(REPO_URL)" ]; then \
	  echo "ERROR: REPO_URL is empty. Set it in .env or pass on command line." >&2; \
	  echo "  example: make argocd-sync REPO_URL=https://github.com/you/IcerbergDataLake.git" >&2; \
	  exit 1; \
	fi
	REPO_URL=$(REPO_URL) TARGET_REVISION=$(TARGET_REVISION) \
	  bash $(ROOT_DIR)/bootstrap/argocd-sync.sh

.PHONY: up
up: kind-up bootstrap image secrets argocd-sync ## End-to-end: cluster + bootstrap + image + secrets + argocd
	@echo
	@echo "Cluster ready. Watch Argo CD sync everything:"
	@echo "  kubectl -n argocd get applications -w"
	@echo
	@echo "URLs (after Argo CD finishes syncing):"
	@echo "  Argo CD : http://argocd.$(INGRESS_DOMAIN)"
	@echo "  Airflow : http://airflow.$(INGRESS_DOMAIN)"
	@echo "  Trino   : http://trino.$(INGRESS_DOMAIN)"
	@echo "  Nessie  : http://nessie.$(INGRESS_DOMAIN)/api/v2/config"
	@echo "  Grafana : http://grafana.$(INGRESS_DOMAIN)"

.PHONY: down
down: kind-down ## Tear everything down (alias for kind-down)

##@ Smoke test
.PHONY: smoke
smoke: ## Run the demo SparkApplication and verify Trino can read it
	bash $(ROOT_DIR)/scripts/smoke.sh

##@ Diagnostics
.PHONY: status
status: ## Show platform pod status across mlops/argocd/monitoring
	@echo '== mlops =='     && kubectl -n mlops get pods,sparkapplications 2>/dev/null || true
	@echo '== argocd =='    && kubectl -n argocd get applications,pods 2>/dev/null || true
	@echo '== monitoring ==' && kubectl -n monitoring get pods 2>/dev/null || true

.PHONY: argocd-password
argocd-password: ## Print the initial Argo CD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath='{.data.password}' | base64 -d ; echo

.PHONY: clean-spark
clean-spark: ## Delete any leftover SparkApplication CRs in mlops
	-kubectl -n mlops delete sparkapplication --all
