# Secrets

This folder is **gitignored** except for the `*.example` templates and `create.sh`.
Never commit a populated `.env` file.

## Setup

```bash
cp secrets/aws-creds.env.example secrets/aws-creds.env
# edit and fill in real AWS values

cp secrets/grafana-admin.env.example secrets/grafana-admin.env
# edit and set a real password
```

Then create the Kubernetes Secrets:

```bash
make secrets   # or: bash secrets/create.sh
```

`create.sh` is idempotent — re-run it after rotating an AWS key.
