from __future__ import annotations

from datetime import datetime

import pandas as pd
import requests
from sqlalchemy import create_engine

from airflow import DAG
from airflow.operators.python import PythonOperator


SOURCE_SQLALCHEMY_URL = "postgresql+psycopg2://airflow:airflow@airflow-postgres:5432/airflow"
SOURCE_TABLE = "public.my_source_table"

TRINO_URL = "http://trino:8080/v1/statement"
TRINO_CATALOG = "iceberg"
TRINO_SCHEMA = "staging"
TRINO_TABLE = "my_source_table"


def _trino_exec(sql: str) -> None:
    r = requests.post(TRINO_URL, data=sql.encode("utf-8"), headers={"Content-Type": "text/plain"})
    r.raise_for_status()

    j = r.json()
    while "nextUri" in j:
        j = requests.get(j["nextUri"]).json()


def _q(val) -> str:
    if val is None or (isinstance(val, float) and pd.isna(val)):
        return "NULL"
    return "'" + str(val).replace("'", "''") + "'"


def extract_and_load() -> None:
    engine = create_engine(SOURCE_SQLALCHEMY_URL)
    df = pd.read_sql(f"SELECT * FROM {SOURCE_TABLE}", engine)

    full_name = f"{TRINO_CATALOG}.{TRINO_SCHEMA}.{TRINO_TABLE}"
    cols = ", ".join(f"\"{c}\" VARCHAR" for c in df.columns)

    _trino_exec(f"CREATE SCHEMA IF NOT EXISTS {TRINO_CATALOG}.{TRINO_SCHEMA}")
    _trino_exec(f"DROP TABLE IF EXISTS {full_name}")
    _trino_exec(f"CREATE TABLE {full_name} ({cols})")

    if df.empty:
        return

    values = []
    for row in df.itertuples(index=False, name=None):
        values.append("(" + ", ".join(_q(v) for v in row) + ")")

    _trino_exec(f"INSERT INTO {full_name} VALUES " + ", ".join(values))


with DAG(
    dag_id="ingest_table_to_trino",
    start_date=datetime(2024, 1, 1),
    schedule=None,
    catchup=False,
) as dag:
    PythonOperator(task_id="extract_and_load", python_callable=extract_and_load)

