# Custom Spark image with Iceberg + AWS jars baked in. Eliminates the
# spec.deps.packages runtime download (and the Ivy /nonexistent cache issue)
# that plagued the original setup.
#
# Base: official Apache Spark 3.5.6 PySpark image (Java 17, Python 3).
ARG SPARK_VERSION=3.5.6
ARG SCALA_VERSION=2.12
ARG ICEBERG_VERSION=1.10.1
ARG HADOOP_AWS_VERSION=3.3.6
ARG AWS_SDK_VERSION=1.12.262

FROM apache/spark:${SPARK_VERSION}-python3 AS jars

ARG SPARK_VERSION
ARG SCALA_VERSION
ARG ICEBERG_VERSION
ARG HADOOP_AWS_VERSION
ARG AWS_SDK_VERSION

USER root

# Drop Iceberg + Iceberg-AWS-Bundle (uses bundled SDK v2 internally) plus the
# legacy hadoop-aws path for compatibility with Spark callers that still pick
# s3a://. Iceberg's own S3FileIO is the preferred path and only needs the bundle.
RUN set -eux; \
    cd /opt/spark/jars; \
    curl -fsSL -O "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_${SCALA_VERSION}/${ICEBERG_VERSION}/iceberg-spark-runtime-3.5_${SCALA_VERSION}-${ICEBERG_VERSION}.jar"; \
    curl -fsSL -O "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/${ICEBERG_VERSION}/iceberg-aws-bundle-${ICEBERG_VERSION}.jar"; \
    curl -fsSL -O "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_AWS_VERSION}/hadoop-aws-${HADOOP_AWS_VERSION}.jar"; \
    curl -fsSL -O "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/${AWS_SDK_VERSION}/aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar"

# Final image
FROM apache/spark:${SPARK_VERSION}-python3

USER root

# Sensible defaults for the spark uid (185). HOME=/nonexistent in the base
# image breaks anything that touches ~/.ivy2 even if we drop spec.deps.packages.
ENV HOME=/tmp \
    SPARK_USER=spark

COPY --from=jars /opt/spark/jars/ /opt/spark/jars/

# Drop back to the unprivileged user the operator expects.
USER 185
