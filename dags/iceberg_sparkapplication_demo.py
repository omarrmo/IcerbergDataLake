"""Submit the demo Iceberg SparkApplication and wait for it to finish.

Uses the SparkKubernetesOperator from apache-airflow-providers-cncf-kubernetes,
which is the production-grade way to run Spark on Kubernetes from Airflow:

  * The operator creates a SparkApplication CR; the Spark Operator launches
    driver + executor pods.
  * The matching SparkKubernetesSensor watches the CR's status and succeeds
    when the application reaches COMPLETED.
  * Airflow's worker SA needs RBAC on sparkapplications.sparkoperator.k8s.io —
    granted by platform/rbac/airflow-spark.yaml.

The SparkApplication template lives in this same git repo and is mounted by
git-sync at /opt/airflow/dags/repo/jobs/iceberg-write/sparkapplication.yaml.
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.spark_kubernetes import (
    SparkKubernetesOperator,
)
from airflow.providers.cncf.kubernetes.sensors.spark_kubernetes import (
    SparkKubernetesSensor,
)


REPO_ROOT = os.environ.get("ICEBERG_REPO_ROOT", "/opt/airflow/dags/repo")
SPARK_APP_FILE = os.path.join(
    REPO_ROOT, "jobs", "iceberg-write", "sparkapplication.yaml"
)

NAMESPACE = "mlops"
APPLICATION_NAME = "iceberg-write-demo"

default_args = {
    "owner": "data-platform",
    "retries": 0,
    "retry_delay": timedelta(minutes=2),
}

with DAG(
    dag_id="iceberg_sparkapplication_demo",
    description="Run the Iceberg-on-S3 demo Spark job via the Spark Operator.",
    default_args=default_args,
    start_date=datetime(2024, 1, 1),
    schedule=None,
    catchup=False,
    tags=["iceberg", "spark", "demo"],
) as dag:
    submit = SparkKubernetesOperator(
        task_id="submit_sparkapplication",
        namespace=NAMESPACE,
        application_file=SPARK_APP_FILE,
        kubernetes_conn_id="kubernetes_default",
        # Delete previous run so re-launching the DAG is idempotent.
        delete_on_termination=True,
        do_xcom_push=False,
    )

    wait = SparkKubernetesSensor(
        task_id="wait_for_completion",
        namespace=NAMESPACE,
        application_name=APPLICATION_NAME,
        kubernetes_conn_id="kubernetes_default",
        attach_log=True,
        poke_interval=15,
        timeout=60 * 30,
    )

    submit >> wait
