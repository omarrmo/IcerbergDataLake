"""Demo Spark job: create an Iceberg namespace + table in the Nessie catalog
and write a couple of rows to it. The catalog/warehouse settings come from the
SparkApplication's sparkConf so this script stays small."""

from pyspark.sql import SparkSession


def main() -> None:
    spark = (
        SparkSession.builder.appName("iceberg-write-demo").getOrCreate()
    )

    spark.sql("CREATE NAMESPACE IF NOT EXISTS nessie.demo")
    spark.sql(
        "CREATE TABLE IF NOT EXISTS nessie.demo.hello "
        "(id INT, txt STRING) USING iceberg"
    )
    spark.sql(
        "INSERT INTO nessie.demo.hello VALUES (1, 'hi'), (2, 'from-spark-on-k8s')"
    )
    spark.sql("SELECT * FROM nessie.demo.hello ORDER BY id").show(truncate=False)

    spark.stop()


if __name__ == "__main__":
    main()
