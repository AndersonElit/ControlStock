"""OpenFaaS Function — capa de formatos del subsistema de reportería.

Invocada por el Kafka Connector de OpenFaaS cuando llega un mensaje en el topic controlstock.reporting.parquet-generado.
Cada mensaje lleva el campo `format` (singular: "CSV" o "XLS").
El report-etl-service publica UN mensaje por formato; esta función lo genera directamente.

Flujo: Kafka controlstock.reporting.parquet-generado → leer parquet (MinIO) → generar format → escribir output/<fmt>/...
Errores → publica ReportETLFailed en Kafka (report.processing.failed).

Secrets montados por OpenFaaS en /var/openfaas/secrets/:
  - report-minio-access-key   (kubernetes_secret en terraform/reporting/)
  - report-minio-secret-key   (kubernetes_secret en terraform/reporting/)
"""
import json
import os
import io
import csv
import logging
from pathlib import Path

import boto3
import pyarrow.dataset as ds
import pyarrow.fs as pafs
from openpyxl import Workbook

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

REPORT_BUCKET    = os.environ.get("REPORT_BUCKET",   "controlstock-reports")
STORAGE_ENDPOINT = os.environ.get("STORAGE_ENDPOINT", "http://minio.infra.svc.cluster.local:9000")
KAFKA_BOOTSTRAP  = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "kafka-kafka-bootstrap.messaging.svc.cluster.local:9092")
FAILED_TOPIC     = "report.processing.failed"
DEFAULT_FORMAT   = "CSV"


def _read_secret(name: str, env_fallback: str, default: str = "") -> str:
    try:
        return Path(f"/var/openfaas/secrets/{name}").read_text().strip()
    except FileNotFoundError:
        return os.environ.get(env_fallback, default)


def _s3_client():
    return boto3.client(
        "s3",
        endpoint_url=STORAGE_ENDPOINT,
        aws_access_key_id=_read_secret("report-minio-access-key", "STORAGE_ACCESS_KEY", "minioadmin"),
        aws_secret_access_key=_read_secret("report-minio-secret-key", "STORAGE_SECRET_KEY", "changeme_minio"),
    )


def _s3fs():
    return pafs.S3FileSystem(
        endpoint_override=STORAGE_ENDPOINT,
        scheme="http" if STORAGE_ENDPOINT else "https",
        access_key=_read_secret("report-minio-access-key", "STORAGE_ACCESS_KEY", "minioadmin"),
        secret_key=_read_secret("report-minio-secret-key", "STORAGE_SECRET_KEY", "changeme_minio"),
    )


def _publish_failed(report_id: str, fmt: str, reason: str) -> None:
    try:
        from kafka import KafkaProducer
        p = KafkaProducer(
            bootstrap_servers=KAFKA_BOOTSTRAP,
            value_serializer=lambda v: json.dumps(v).encode("utf-8"),
        )
        p.send(FAILED_TOPIC, key=f"{report_id}-{fmt}".encode(), value={
            "reportId": report_id,
            "stage": "format-generation",
            "format": fmt,
            "reason": reason,
        })
        p.flush()
        p.close()
    except Exception as exc:
        logger.warning("No se pudo publicar ReportETLFailed: %s", exc)


def _process_message(msg: dict) -> dict:
    report_id   = msg.get("reportId", "unknown")
    report_type = msg.get("reportType", "report")
    parquet_uri = msg.get("processedParquetUri") or msg.get("rawParquetUri", "")
    fmt         = (msg.get("format") or DEFAULT_FORMAT).upper()

    if not parquet_uri:
        logger.error("processedParquetUri vacío para reportId=%s", report_id)
        _publish_failed(report_id, fmt, "processedParquetUri vacío")
        return {}

    try:
        table = ds.dataset(parquet_uri, format="parquet", filesystem=_s3fs()).to_table()
    except Exception as exc:
        logger.error("Error leyendo parquet %s: %s", parquet_uri, exc)
        _publish_failed(report_id, fmt, f"Error leyendo parquet: {exc}")
        return {}

    s3 = _s3_client()

    try:
        if fmt == "CSV":
            buf = io.StringIO()
            writer = csv.writer(buf)
            writer.writerow(table.column_names)
            for row in zip(*[col.to_pylist() for col in table.columns]):
                writer.writerow(row)
            key = f"output/csv/{report_type}/{report_id}.csv"
            s3.put_object(
                Bucket=REPORT_BUCKET,
                Key=key,
                Body=buf.getvalue().encode("utf-8"),
                ContentType="text/csv",
            )

        elif fmt == "XLS":
            wb = Workbook()
            ws = wb.active
            ws.title = report_type[:31]
            ws.append(table.column_names)
            for row in zip(*[col.to_pylist() for col in table.columns]):
                ws.append(list(row))
            buf = io.BytesIO()
            wb.save(buf)
            key = f"output/xls/{report_type}/{report_id}.xlsx"
            s3.put_object(
                Bucket=REPORT_BUCKET,
                Key=key,
                Body=buf.getvalue(),
                ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            )

        else:
            logger.warning("Formato no soportado: %s", fmt)
            _publish_failed(report_id, fmt, f"Formato no soportado: {fmt}")
            return {}

        output_uri = f"s3://{REPORT_BUCKET}/{key}"
        logger.info("Generado %s → %s (%d filas)", fmt, output_uri, table.num_rows)
        return {"format": fmt, "output": output_uri, "rows": table.num_rows}

    except Exception as exc:
        logger.error("Error generando %s para reportId=%s: %s", fmt, report_id, exc)
        _publish_failed(report_id, fmt, f"Error generando {fmt}: {exc}")
        return {}


def handle(event, context):
    """Entrypoint OpenFaaS — el Kafka Connector envía el mensaje Kafka como body HTTP."""
    body = event.body
    if isinstance(body, bytes):
        body = body.decode("utf-8")

    try:
        msg = json.loads(body)
    except json.JSONDecodeError as exc:
        logger.error("Body no es JSON válido: %s", exc)
        return {"statusCode": 400, "body": json.dumps({"error": "invalid JSON"})}

    result = _process_message(msg)

    if result:
        return {"statusCode": 200, "body": json.dumps({"generated": 1, "outputs": [result]})}
    return {"statusCode": 500, "body": json.dumps({"generated": 0, "outputs": []})}
