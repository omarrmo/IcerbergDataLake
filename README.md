# IcerbergDataLake

Local Kind-based Iceberg lakehouse, structured the way an on-prem company would
run it: GitOps with Argo CD, Helm-managed components, ingress at
`*.localtest.me`, observability via kube-prometheus-stack.

```
Airflow  ->  Spark Operator  ->  Iceberg(S3FileIO)  ->  AWS S3
                                       ^
                                       |
                                     Nessie  <-  Trino
                                       |
                                   PostgreSQL
```

See [docs/architecture.md](docs/architecture.md) for the full diagram and
folder map.

## Prerequisites

- `docker` (Apple Silicon or x86)
- `kind`
- `kubectl`
- `helm`
- `gettext` (for `envsubst`) - `brew install gettext`
- `aws` CLI (optional, for S3 verification)
- `trino` CLI (optional, for the smoke test's read step)

## One-time setup

1. **Fork or push this repo somewhere Argo CD can reach.** Argo CD pulls
   `platform/`, `dags/`, and `jobs/` over HTTPS. Set `REPO_URL` to the URL
   of your fork.

2. **Provide AWS credentials out-of-band.** Never commit them.

   ```bash
   cp secrets/aws-creds.env.example secrets/aws-creds.env
   # edit secrets/aws-creds.env and fill in a fresh IAM key
   ```

3. **Optional: Grafana admin password.**

   ```bash
   cp secrets/grafana-admin.env.example secrets/grafana-admin.env
   # edit and set a real password
   ```

4. **Optional: a `.env` for tunables.**

   ```bash
   cp .env.example .env
   # edit S3_BUCKET, INGRESS_DOMAIN, KIND_CLUSTER_NAME, REPO_URL, ...
   ```

## Bring it up

```bash
make up REPO_URL=https://github.com/<you>/IcerbergDataLake.git
```

That single target:

1. creates the Kind cluster (`cluster/kind.yaml`)
2. installs ingress-nginx + Argo CD (`bootstrap/install.sh`)
3. builds the custom Spark image and loads it into Kind (`images/spark/`)
4. creates the `aws-creds` (and optional `grafana-admin`) Secrets
5. applies the root Argo Application — Argo CD then reconciles everything else.

After it returns, watch Argo CD finish the sync:

```bash
kubectl -n argocd get applications -w
make status
```

## Endpoints

`localtest.me` resolves to `127.0.0.1` automatically — no `/etc/hosts` edits
needed.

| What    | URL                                     | Login                       |
| ------- | --------------------------------------- | --------------------------- |
| Argo CD | `http://argocd.localtest.me`            | `admin` / `make argocd-password` |
| Airflow | `http://airflow.localtest.me`           | `admin` / `admin`           |
| Trino   | `http://trino.localtest.me`             | -                           |
| Nessie  | `http://nessie.localtest.me/api/v2/config` | -                       |
| Grafana | `http://grafana.localtest.me`           | from `secrets/grafana-admin.env` |

## Run the demo

The Airflow DAG `iceberg_sparkapplication_demo` submits the demo
`SparkApplication`. Trigger it from the UI or via CLI.

Headless smoke test (driver logs + a Trino SELECT):

```bash
make smoke
```

## Tear down

```bash
make down
```

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `ImagePullBackOff` for `bitnami/spark:*` | Bitnami images moved to `bitnamilegacy/` in 2026 | Rebuild custom image: `make image` |
| Spark driver fails on `/nonexistent/.ivy2…` | Image tries to download Maven deps at submit time | Drop `spec.deps.packages` (already done); custom image bakes them in |
| Trino `S3 AccessDenied` | Coordinator/worker has no AWS creds | Verify `aws-creds` Secret exists; `make secrets` to refresh; pods auto-restart |
| Argo CD stuck on `OutOfSync` for `kube-prometheus-stack` | CRDs too large for default ServerSideApply | Already mitigated with `ApplyOutOfSyncOnly=true`; if still stuck, `kubectl -n argocd patch app kube-prometheus-stack --type merge -p '{"operation":{"sync":{"prune":true}}}'` |
| `nessie` pod CrashLoopBackOff | Postgres not ready yet | Wait for `postgres-postgresql-0` to be `Running`; nessie self-heals |
| Airflow can't create `SparkApplication` | Worker SA missing RBAC | Ensure `platform/rbac/airflow-spark.yaml` is applied (`kubectl -n mlops get role airflow-spark`) |

## Make targets

```
make help              # all targets
make up                # cluster + bootstrap + image + secrets + argocd
make down              # delete the Kind cluster
make image             # rebuild the custom Spark image
make secrets           # (re)create K8s Secrets from secrets/*.env
make smoke             # end-to-end Spark write + Trino read
make status            # pod overview across all namespaces
make argocd-password   # print the Argo CD admin password
make clean-spark       # delete leftover SparkApplication CRs
```
