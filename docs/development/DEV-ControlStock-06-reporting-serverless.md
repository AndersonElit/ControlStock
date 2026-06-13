# Etapa 6 — Reportería Serverless: report-format-consumer (OpenFaaS)

## Índice

1. [Objetivo y Contexto](#1-objetivo-y-contexto)
2. [Prerrequisitos](#2-prerrequisitos)
3. [Scaffolding y Artefactos Generados](#3-scaffolding-y-artefactos-generados)
4. [Implementación del Handler (TDD — Red-Green-Refactor)](#4-implementación-del-handler-tdd--red-green-refactor)
5. [TDD — Pruebas (pytest)](#5-tdd--pruebas-pytest)
6. [Despliegue en K3s (local y prod)](#6-despliegue-en-k3s-local-y-prod)
7. [Integración con el Pipeline CI/CD](#7-integración-con-el-pipeline-cicd)
8. [Criterios de Aceptación](#8-criterios-de-aceptación)

---

## 1. Objetivo y Contexto

`report-format-consumer` es una función serverless OpenFaaS que opera como el último eslabón del pipeline de reportería de ControlStock. Su responsabilidad exclusiva es **convertir archivos `.parquet` en formatos consumibles por el negocio** (XLSX, CSV, PDF) y notificar al `report-service` sobre la finalización del proceso.

A diferencia de los microservicios del sistema, esta unidad **no expone endpoints HTTP propios de negocio** — es activada por eventos Kafka y escala a cero cuando no hay trabajo pendiente.

### Posición en el Pipeline de Reportería

```
┌─────────────────┐   POST /reports/{id}/generar   ┌──────────────────────┐
│  report-service │ ─────────────────────────────► │  report-etl-service  │
│  (Spring Boot)  │                                 │  (Spring Boot/Camel) │
└────────┬────────┘                                 └──────────┬───────────┘
         │                                                     │
         │  POST /reports/{id}/completar (callback)            │ lee MongoDB
         │  ◄──────────────────────────────────────────────    │ transforma datos
         │                                                     │ escribe .parquet → MinIO
         │                                                     │
         │                                         ┌──────────▼───────────┐
         │                                         │        MinIO         │
         │                                         │  controlstock-reports│
         │                                         │  /parquet/{type}/    │
         │                                         │  {year}/{month}/     │
         │                                         │  {requestId}.parquet │
         │                                         └──────────┬───────────┘
         │                                                     │
         │                                         ┌──────────▼───────────┐
         │                                         │        Kafka         │
         │                                         │  ReporteParquetGen.  │
         │                                         └──────────┬───────────┘
         │                                                     │
         │                                         ┌──────────▼───────────┐
         │                                         │ report-format-       │
         │◄────────────────────────────────────────┤ consumer (OpenFaaS)  │
         │  POST /reports/{id}/completar            │  openfaas-fn NS      │
                                                   └──────────┬───────────┘
                                                              │ escribe output
                                                   ┌──────────▼───────────┐
                                                   │        MinIO         │
                                                   │  /output/xlsx|csv|   │
                                                   │  pdf/{requestId}.ext │
                                                   └──────────────────────┘
```

### Flujo de Eventos

| Paso | Actor | Acción | Topic / Endpoint |
|------|-------|--------|-----------------|
| 1 | report-etl-service | Genera `.parquet` y publica evento | `controlstock.reporting.parquet-generado` |
| 2 | Kafka Connector | Entrega evento a la función | HTTP POST interno OpenFaaS |
| 3 | report-format-consumer | Lee `.parquet` de MinIO | MinIO S3 API |
| 4 | report-format-consumer | Convierte al formato solicitado | pandas / openpyxl / reportlab |
| 5 | report-format-consumer | Escribe archivo final en MinIO | MinIO S3 API |
| 6 | report-format-consumer | Notifica finalización | `POST /reports/{id}/completar` |
| Error | report-format-consumer | Publica evento de fallo | `controlstock.reporting.etl-fallido` |

---

## 2. Prerrequisitos

### Infraestructura (Etapa 0)

Todos los siguientes componentes deben estar operativos antes de ejecutar esta etapa. Se instalan mediante `base-infrastructure-builder.sh` con el módulo `helm-support`.

```bash
# Verificar OpenFaaS operativo
kubectl get pods -n openfaas
# Esperado: gateway, queue-worker, prometheus, alertmanager → Running

# Verificar Kafka Connector instalado
kubectl get pods -n openfaas -l app=kafka-connector
# Esperado: kafka-connector-* → Running

# Verificar faas-cli disponible
faas-cli version
```

### Servicios de Negocio

| Servicio | Estado requerido | Verificación |
|---------|-----------------|--------------|
| `report-etl-service` | Deployed + Running | `kubectl get pod -n apps -l app=report-etl-service` |
| `report-service` | Deployed + Running | `kubectl get pod -n apps -l app=report-service` |
| MinIO | Accessible | `curl http://<VPS_IP>:9001/minio/health/live` |
| Kafka | Accessible | `kubectl get pod -n messaging -l app.kubernetes.io/name=kafka` |

### Bucket MinIO

```bash
# Verificar buckets existentes (creados en Etapa 1)
mc alias set local http://<VPS_IP>:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
mc ls local/controlstock-reports
# Esperado: parquet/ y output/ directorios presentes
```

### Credenciales y Secrets

```bash
# Verificar secret MinIO en namespace openfaas-fn
kubectl get secret minio-credentials -n openfaas-fn
```

---

## 3. Scaffolding y Artefactos Generados

### Comando de Scaffolding

El scaffolding se ejecuta desde `scaffold-all-services.sh` con la opción `--report-formats`:

```bash
python3 .claude/templates/report_lambdas_scaffold.py \
  --org controlstock \
  --kafka-topic controlstock.reporting.parquet-generado \
  --image-registry <VPS_IP>:3000/controlstock \
  --report-formats xlsx,csv,pdf
```

O directamente desde `scaffold-all-services.sh`:

```bash
bash scripts/scaffold-all-services.sh --report-formats xlsx,csv,pdf
```

### Árbol de Artefactos Generados

```
functions/
└── report-format-consumer/
    ├── handler.py                    # Handler principal de la función
    ├── requirements.txt              # Dependencias Python
    ├── event_schema.py               # Validación Pydantic del evento Kafka
    ├── converters/
    │   ├── __init__.py
    │   ├── xlsx_converter.py         # pandas + openpyxl
    │   ├── csv_converter.py          # pandas to_csv
    │   └── pdf_converter.py          # reportlab
    └── tests/
        ├── __init__.py
        ├── conftest.py               # fixtures pytest + Testcontainers
        ├── test_handler.py           # tests del handler principal
        ├── test_xlsx_converter.py
        ├── test_csv_converter.py
        ├── test_pdf_converter.py
        └── test_e2e_reporting.py     # E2E con Testcontainers MinIO

stack.yml                             # Configuración faas-cli deployment

helm/
└── report-format-consumer/
    ├── Chart.yaml
    ├── values.yaml                   # valores base
    └── values-local.yaml            # override local: registry, topic, broker

scripts/
├── deploy.sh                         # Script de despliegue completo
└── create-minio-secrets.sh          # Crea K8s secrets para credenciales MinIO
```

### Descripción de Archivos Clave

#### `stack.yml`

```yaml
version: 1.0
provider:
  name: openfaas
  gateway: http://127.0.0.1:8080

functions:
  report-format-consumer:
    lang: python3-http
    handler: ./functions/report-format-consumer
    image: <VPS_IP>:3000/controlstock/report-format-consumer:latest
    namespace: openfaas-fn
    environment:
      MINIO_ENDPOINT: "minio.storage.svc.cluster.local:9000"
      MINIO_BUCKET_INPUT: "controlstock-reports"
      MINIO_BUCKET_OUTPUT: "controlstock-reports"
      REPORT_SERVICE_URL: "http://report-service.apps.svc.cluster.local:8087"
      KAFKA_BROKER: "kafka-kafka-bootstrap.messaging.svc.cluster.local:9092"
      KAFKA_ERROR_TOPIC: "controlstock.reporting.etl-fallido"
    secrets:
      - minio-credentials
    annotations:
      topic: "controlstock.reporting.parquet-generado"
    limits:
      memory: 512Mi
      cpu: 200m
    requests:
      memory: 128Mi
      cpu: 50m
```

#### `requirements.txt`

```
pandas==2.2.2
pyarrow==16.1.0
openpyxl==3.1.4
reportlab==4.2.2
minio==7.2.7
confluent-kafka==2.4.0
pydantic==2.7.4
requests==2.32.3
```

#### `helm/report-format-consumer/values-local.yaml`

```yaml
openfaas:
  gateway: http://gateway.openfaas.svc.cluster.local:8080
  functionNamespace: openfaas-fn

kafkaConnector:
  topics: "controlstock.reporting.parquet-generado"
  brokerHosts: "kafka-kafka-bootstrap.messaging.svc.cluster.local:9092"
  groupId: "report-format-consumer-group"

function:
  image: "<VPS_IP>:3000/controlstock/report-format-consumer:latest"
  replicas:
    min: 0
    max: 5

minio:
  endpoint: "minio.storage.svc.cluster.local:9000"
  bucketInput: "controlstock-reports"
  bucketOutput: "controlstock-reports"

reportService:
  url: "http://report-service.apps.svc.cluster.local:8087"
```

#### `scripts/create-minio-secrets.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="openfaas-fn"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-controlstock}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-changeme}"

kubectl create secret generic minio-credentials \
  --namespace "$NAMESPACE" \
  --from-literal=MINIO_ACCESS_KEY="$MINIO_ACCESS_KEY" \
  --from-literal=MINIO_SECRET_KEY="$MINIO_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret minio-credentials creado/actualizado en namespace $NAMESPACE"
```

---

## 4. Implementación del Handler (TDD — Red-Green-Refactor)

### 4.1 Schema de Validación del Evento (Pydantic)

**Archivo:** `functions/report-format-consumer/event_schema.py`

El evento `ReporteParquetGenerado` publicado por `report-etl-service` tiene la siguiente estructura:

```python
from pydantic import BaseModel, Field
from typing import Literal
from datetime import datetime


class ReporteParquetGenerado(BaseModel):
    """Schema de validación para el evento Kafka ReporteParquetGenerado."""

    evento: Literal["ReporteParquetGenerado"] = "ReporteParquetGenerado"
    reporteId: str = Field(..., description="UUID del reporte en report-service")
    requestId: str = Field(..., description="UUID único de la solicitud de generación")
    reportType: str = Field(..., description="Tipo de reporte: STOCK_ACTUAL, MOVIMIENTOS, etc.")
    formatoDestino: Literal["XLSX", "CSV", "PDF"] = Field(
        ..., description="Formato de salida solicitado"
    )
    parquetPath: str = Field(
        ...,
        description="Ruta relativa en MinIO: parquet/{report_type}/{year}/{month}/{request_id}.parquet"
    )
    generadoPor: str = Field(..., description="Usuario que solicitó el reporte")
    timestamp: datetime = Field(..., description="Timestamp de generación del parquet")

    @property
    def output_extension(self) -> str:
        return self.formatoDestino.lower()

    @property
    def output_path(self) -> str:
        return f"output/{self.formatoDestino.lower()}/{self.requestId}.{self.output_extension}"


class EventoError(BaseModel):
    """Schema para publicar eventos de error al topic etl-fallido."""

    evento: Literal["ReporteETLFallido"] = "ReporteETLFallido"
    reporteId: str
    requestId: str
    causa: str
    detalle: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
```

### 4.2 Estructura del Handler Principal

**Archivo:** `functions/report-format-consumer/handler.py`

```python
import json
import os
import io
import logging
from datetime import datetime

import requests
from minio import Minio
from minio.error import S3Error
from confluent_kafka import Producer

from event_schema import ReporteParquetGenerado, EventoError
from converters.xlsx_converter import convertir_a_xlsx
from converters.csv_converter import convertir_a_csv
from converters.pdf_converter import convertir_a_pdf
from pydantic import ValidationError

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

# ── Constantes de entorno ──────────────────────────────────────────────────────
MINIO_ENDPOINT = os.environ["MINIO_ENDPOINT"]
MINIO_ACCESS_KEY = os.environ["MINIO_ACCESS_KEY"]
MINIO_SECRET_KEY = os.environ["MINIO_SECRET_KEY"]
MINIO_BUCKET = os.environ.get("MINIO_BUCKET_INPUT", "controlstock-reports")
REPORT_SERVICE_URL = os.environ["REPORT_SERVICE_URL"]
KAFKA_BROKER = os.environ.get("KAFKA_BROKER", "")
KAFKA_ERROR_TOPIC = os.environ.get("KAFKA_ERROR_TOPIC", "controlstock.reporting.etl-fallido")

# ── Converters registrados ────────────────────────────────────────────────────
CONVERTERS = {
    "XLSX": convertir_a_xlsx,
    "CSV": convertir_a_csv,
    "PDF": convertir_a_pdf,
}

# ── Content types por formato ─────────────────────────────────────────────────
CONTENT_TYPES = {
    "XLSX": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "CSV": "text/csv",
    "PDF": "application/pdf",
}


def handle(event, context):
    """
    Handler principal de la función OpenFaaS.

    Flujo:
    1. Validar evento Kafka (Pydantic)
    2. Leer .parquet desde MinIO
    3. Convertir al formato solicitado (XLSX / CSV / PDF)
    4. Escribir archivo final en MinIO output/
    5. Notificar a report-service vía callback REST
    """
    body = event.body

    # ── Paso 1: Deserializar y validar evento ─────────────────────────────────
    try:
        payload = json.loads(body) if isinstance(body, (str, bytes)) else body
        evento = ReporteParquetGenerado(**payload)
    except (json.JSONDecodeError, ValidationError) as exc:
        logger.error("Evento inválido recibido: %s", exc)
        return {"statusCode": 400, "body": f"Evento inválido: {exc}"}

    logger.info(
        "Procesando reporte %s (formato=%s, parquet=%s)",
        evento.reporteId, evento.formatoDestino, evento.parquetPath
    )

    minio_client = _build_minio_client()

    # ── Paso 2: Leer .parquet desde MinIO ────────────────────────────────────
    try:
        parquet_bytes = _leer_parquet(minio_client, evento.parquetPath)
    except S3Error as exc:
        logger.error("Error leyendo parquet de MinIO: %s", exc)
        _publicar_error(evento, f"Error accediendo MinIO: {exc}")
        return {"statusCode": 500, "body": "Error leyendo archivo parquet"}

    # ── Paso 3: Convertir al formato destino ─────────────────────────────────
    converter = CONVERTERS.get(evento.formatoDestino)
    if not converter:
        msg = f"Formato no soportado: {evento.formatoDestino}"
        logger.error(msg)
        _publicar_error(evento, msg)
        return {"statusCode": 422, "body": msg}

    try:
        output_bytes: bytes = converter(parquet_bytes)
    except Exception as exc:
        logger.error("Error en conversión %s: %s", evento.formatoDestino, exc)
        _publicar_error(evento, f"Error de conversión: {exc}")
        return {"statusCode": 500, "body": f"Error en conversión: {exc}"}

    # ── Paso 4: Escribir en MinIO output/ ────────────────────────────────────
    try:
        _escribir_output(
            minio_client,
            output_path=evento.output_path,
            data=output_bytes,
            content_type=CONTENT_TYPES[evento.formatoDestino],
        )
    except S3Error as exc:
        logger.error("Error escribiendo output en MinIO: %s", exc)
        _publicar_error(evento, f"Error escribiendo output MinIO: {exc}")
        return {"statusCode": 500, "body": "Error escribiendo archivo de salida"}

    # ── Paso 5: Notificar a report-service ───────────────────────────────────
    try:
        _notificar_completado(evento)
    except requests.RequestException as exc:
        # Loguear pero no fallar — el archivo ya está en MinIO
        logger.warning("No se pudo notificar al report-service: %s", exc)

    logger.info("Reporte %s generado exitosamente en %s", evento.reporteId, evento.output_path)
    return {
        "statusCode": 200,
        "body": json.dumps({
            "reporteId": evento.reporteId,
            "outputPath": evento.output_path,
            "estado": "COMPLETADO"
        })
    }


# ── Funciones auxiliares ──────────────────────────────────────────────────────

def _build_minio_client() -> Minio:
    return Minio(
        MINIO_ENDPOINT,
        access_key=MINIO_ACCESS_KEY,
        secret_key=MINIO_SECRET_KEY,
        secure=False,
    )


def _leer_parquet(client: Minio, path: str) -> bytes:
    response = client.get_object(MINIO_BUCKET, path)
    try:
        return response.read()
    finally:
        response.close()
        response.release_conn()


def _escribir_output(client: Minio, output_path: str, data: bytes, content_type: str) -> None:
    client.put_object(
        MINIO_BUCKET,
        output_path,
        data=io.BytesIO(data),
        length=len(data),
        content_type=content_type,
    )


def _notificar_completado(evento: ReporteParquetGenerado) -> None:
    url = f"{REPORT_SERVICE_URL}/reports/{evento.reporteId}/completar"
    payload = {
        "requestId": evento.requestId,
        "outputPath": evento.output_path,
        "formato": evento.formatoDestino,
        "completadoEn": datetime.utcnow().isoformat(),
    }
    resp = requests.post(url, json=payload, timeout=10)
    resp.raise_for_status()


def _publicar_error(evento: ReporteParquetGenerado, causa: str) -> None:
    if not KAFKA_BROKER:
        logger.warning("KAFKA_BROKER no configurado — omitiendo publicación de error")
        return

    error_evento = EventoError(
        reporteId=evento.reporteId,
        requestId=evento.requestId,
        causa=causa,
        detalle=f"Fallo en report-format-consumer para formato {evento.formatoDestino}",
    )

    producer = Producer({"bootstrap.servers": KAFKA_BROKER})
    producer.produce(
        KAFKA_ERROR_TOPIC,
        key=evento.reporteId.encode(),
        value=error_evento.model_dump_json().encode(),
    )
    producer.flush(timeout=5)
```

### 4.3 Converters por Formato

#### `converters/xlsx_converter.py`

```python
import io
import pandas as pd


def convertir_a_xlsx(parquet_bytes: bytes) -> bytes:
    """Convierte bytes de un archivo .parquet a XLSX usando pandas + openpyxl."""
    df = pd.read_parquet(io.BytesIO(parquet_bytes))

    output = io.BytesIO()
    with pd.ExcelWriter(output, engine="openpyxl") as writer:
        df.to_excel(writer, index=False, sheet_name="Reporte")

    return output.getvalue()
```

#### `converters/csv_converter.py`

```python
import io
import pandas as pd


def convertir_a_csv(parquet_bytes: bytes) -> bytes:
    """Convierte bytes de un archivo .parquet a CSV usando pandas."""
    df = pd.read_parquet(io.BytesIO(parquet_bytes))
    return df.to_csv(index=False).encode("utf-8")
```

#### `converters/pdf_converter.py`

```python
import io
import pandas as pd
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet


def convertir_a_pdf(parquet_bytes: bytes) -> bytes:
    """Convierte bytes de un archivo .parquet a PDF usando reportlab."""
    df = pd.read_parquet(io.BytesIO(parquet_bytes))

    output = io.BytesIO()
    doc = SimpleDocTemplate(output, pagesize=landscape(A4))
    styles = getSampleStyleSheet()
    elements = []

    # Título
    elements.append(Paragraph("Reporte ControlStock", styles["Title"]))
    elements.append(Spacer(1, 12))

    # Tabla de datos
    data = [list(df.columns)] + df.astype(str).values.tolist()
    table = Table(data, repeatRows=1)
    table.setStyle(
        TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#2563EB")),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("FONTSIZE", (0, 0), (-1, 0), 9),
            ("FONTSIZE", (0, 1), (-1, -1), 8),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F1F5F9")]),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#CBD5E1")),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 4),
            ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ])
    )
    elements.append(table)

    doc.build(elements)
    return output.getvalue()
```

### 4.4 Ciclo Red-Green-Refactor

| Fase | Acción |
|------|--------|
| **Red** | Escribir test que falla: `test_handler_routes_by_formato_destino` — el handler no existe aún |
| **Green** | Implementar `handler.py` con routing mínimo — el test pasa |
| **Refactor** | Extraer `_build_minio_client`, `_leer_parquet`, `_escribir_output`, `_notificar_completado` a funciones puras; parametrizar converters en dict `CONVERTERS` |
| **Red** | Test de error: MinIO lanza `S3Error` → el handler debe publicar al topic de error |
| **Green** | Agregar bloque `except S3Error` con llamada a `_publicar_error` |
| **Refactor** | Extraer `_publicar_error`; verificar que no duplica lógica con converters |

---

## 5. TDD — Pruebas (pytest)

### 5.1 Fixtures y Configuración (`conftest.py`)

```python
import io
import json
import pytest
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from unittest.mock import MagicMock, patch
from datetime import datetime


@pytest.fixture
def sample_parquet_bytes() -> bytes:
    """Genera un archivo .parquet en memoria con datos de stock de prueba."""
    df = pd.DataFrame({
        "sku": ["SKU-001", "SKU-002", "SKU-003"],
        "nombre": ["Producto A", "Producto B", "Producto C"],
        "stock": [100, 50, 200],
        "ubicacion": ["A1", "B2", "C3"],
        "ultima_actualizacion": ["2026-06-01", "2026-06-02", "2026-06-03"],
    })
    buf = io.BytesIO()
    df.to_parquet(buf, index=False)
    return buf.getvalue()


@pytest.fixture
def evento_xlsx():
    return {
        "evento": "ReporteParquetGenerado",
        "reporteId": "reporte-uuid-001",
        "requestId": "req-uuid-001",
        "reportType": "STOCK_ACTUAL",
        "formatoDestino": "XLSX",
        "parquetPath": "parquet/STOCK_ACTUAL/2026/06/req-uuid-001.parquet",
        "generadoPor": "admin@controlstock.local",
        "timestamp": datetime.utcnow().isoformat(),
    }


@pytest.fixture
def evento_csv(evento_xlsx):
    return {**evento_xlsx, "formatoDestino": "CSV", "requestId": "req-uuid-002",
            "parquetPath": "parquet/STOCK_ACTUAL/2026/06/req-uuid-002.parquet"}


@pytest.fixture
def evento_pdf(evento_xlsx):
    return {**evento_xlsx, "formatoDestino": "PDF", "requestId": "req-uuid-003",
            "parquetPath": "parquet/STOCK_ACTUAL/2026/06/req-uuid-003.parquet"}


@pytest.fixture
def mock_minio():
    with patch("handler.Minio") as mock:
        yield mock.return_value


@pytest.fixture
def mock_report_service():
    with patch("handler.requests.post") as mock:
        mock.return_value.status_code = 200
        yield mock
```

### 5.2 Pruebas de Conversión de Formatos

```python
# tests/test_xlsx_converter.py
import io
import pytest
import pandas as pd
import openpyxl
from converters.xlsx_converter import convertir_a_xlsx


def test_xlsx_tiene_columnas_correctas(sample_parquet_bytes):
    result = convertir_a_xlsx(sample_parquet_bytes)
    wb = openpyxl.load_workbook(io.BytesIO(result))
    ws = wb.active
    headers = [cell.value for cell in ws[1]]
    assert "sku" in headers
    assert "stock" in headers


def test_xlsx_tiene_datos_completos(sample_parquet_bytes):
    result = convertir_a_xlsx(sample_parquet_bytes)
    wb = openpyxl.load_workbook(io.BytesIO(result))
    ws = wb.active
    # Fila 1 = headers, filas 2-4 = datos
    assert ws.max_row == 4


def test_xlsx_sheet_name_es_reporte(sample_parquet_bytes):
    result = convertir_a_xlsx(sample_parquet_bytes)
    wb = openpyxl.load_workbook(io.BytesIO(result))
    assert "Reporte" in wb.sheetnames
```

```python
# tests/test_csv_converter.py
import io
import pandas as pd
from converters.csv_converter import convertir_a_csv


def test_csv_tiene_header(sample_parquet_bytes):
    result = convertir_a_csv(sample_parquet_bytes)
    lines = result.decode("utf-8").splitlines()
    assert "sku" in lines[0]
    assert "stock" in lines[0]


def test_csv_tiene_todas_las_filas(sample_parquet_bytes):
    result = convertir_a_csv(sample_parquet_bytes)
    df = pd.read_csv(io.BytesIO(result))
    assert len(df) == 3


def test_csv_encoding_utf8(sample_parquet_bytes):
    result = convertir_a_csv(sample_parquet_bytes)
    assert isinstance(result, bytes)
    result.decode("utf-8")  # no debe lanzar excepción
```

```python
# tests/test_pdf_converter.py
from converters.pdf_converter import convertir_a_pdf


def test_pdf_genera_bytes(sample_parquet_bytes):
    result = convertir_a_pdf(sample_parquet_bytes)
    assert isinstance(result, bytes)
    assert len(result) > 0


def test_pdf_inicia_con_magic_bytes(sample_parquet_bytes):
    result = convertir_a_pdf(sample_parquet_bytes)
    # Los PDF inician con %PDF
    assert result[:4] == b"%PDF"


def test_pdf_tiene_datos_no_vacio(sample_parquet_bytes):
    result = convertir_a_pdf(sample_parquet_bytes)
    # Un PDF con datos debe superar 1KB
    assert len(result) > 1024
```

### 5.3 Pruebas del Handler

```python
# tests/test_handler.py
import json
import pytest
from unittest.mock import MagicMock, patch, call
from types import SimpleNamespace


def make_event(body_dict: dict) -> SimpleNamespace:
    return SimpleNamespace(body=json.dumps(body_dict).encode())


class TestHandlerRouting:

    def test_xlsx_llama_converter_xlsx(self, evento_xlsx, sample_parquet_bytes, mock_minio, mock_report_service):
        mock_minio.get_object.return_value = MagicMock(read=lambda: sample_parquet_bytes, close=lambda: None, release_conn=lambda: None)

        with patch("handler.convertir_a_xlsx", return_value=b"xlsx-bytes") as mock_conv:
            from handler import handle
            result = handle(make_event(evento_xlsx), None)

        assert result["statusCode"] == 200
        mock_conv.assert_called_once()

    def test_csv_llama_converter_csv(self, evento_csv, sample_parquet_bytes, mock_minio, mock_report_service):
        mock_minio.get_object.return_value = MagicMock(read=lambda: sample_parquet_bytes, close=lambda: None, release_conn=lambda: None)

        with patch("handler.convertir_a_csv", return_value=b"csv-bytes") as mock_conv:
            from handler import handle
            result = handle(make_event(evento_csv), None)

        assert result["statusCode"] == 200
        mock_conv.assert_called_once()

    def test_pdf_llama_converter_pdf(self, evento_pdf, sample_parquet_bytes, mock_minio, mock_report_service):
        mock_minio.get_object.return_value = MagicMock(read=lambda: sample_parquet_bytes, close=lambda: None, release_conn=lambda: None)

        with patch("handler.convertir_a_pdf", return_value=b"pdf-bytes") as mock_conv:
            from handler import handle
            result = handle(make_event(evento_pdf), None)

        assert result["statusCode"] == 200
        mock_conv.assert_called_once()

    def test_callback_report_service_llamado(self, evento_xlsx, sample_parquet_bytes, mock_minio, mock_report_service):
        mock_minio.get_object.return_value = MagicMock(read=lambda: sample_parquet_bytes, close=lambda: None, release_conn=lambda: None)

        with patch("handler.convertir_a_xlsx", return_value=b"xlsx-bytes"):
            from handler import handle
            handle(make_event(evento_xlsx), None)

        url_llamada = mock_report_service.call_args[0][0]
        assert "/reports/reporte-uuid-001/completar" in url_llamada

    def test_evento_invalido_retorna_400(self, mock_minio, mock_report_service):
        from handler import handle
        result = handle(make_event({"campo_inexistente": "valor"}), None)
        assert result["statusCode"] == 400


class TestHandlerErrorHandling:

    def test_minio_error_publica_al_topic_error(self, evento_xlsx, mock_minio):
        from minio.error import S3Error
        mock_minio.get_object.side_effect = S3Error(
            "NoSuchKey", "Object not found", None, None, None, None
        )

        with patch("handler._publicar_error") as mock_error:
            from handler import handle
            result = handle(make_event(evento_xlsx), None)

        assert result["statusCode"] == 500
        mock_error.assert_called_once()
        args = mock_error.call_args[0]
        assert args[0].reporteId == "reporte-uuid-001"

    def test_formato_no_soportado_retorna_422(self, mock_minio):
        evento_invalido = {
            "evento": "ReporteParquetGenerado",
            "reporteId": "r-001",
            "requestId": "rq-001",
            "reportType": "STOCK",
            "formatoDestino": "XML",  # no soportado
            "parquetPath": "parquet/STOCK/2026/06/rq-001.parquet",
            "generadoPor": "admin",
            "timestamp": "2026-06-13T10:00:00",
        }
        from handler import handle
        result = handle(make_event(evento_invalido), None)
        # Pydantic rechaza "XML" porque no está en Literal["XLSX","CSV","PDF"]
        assert result["statusCode"] == 400

    def test_callback_falla_no_impide_respuesta_200(self, evento_xlsx, sample_parquet_bytes, mock_minio):
        import requests as req_module
        mock_minio.get_object.return_value = MagicMock(read=lambda: sample_parquet_bytes, close=lambda: None, release_conn=lambda: None)

        with patch("handler.convertir_a_xlsx", return_value=b"xlsx-bytes"):
            with patch("handler.requests.post", side_effect=req_module.ConnectionError("timeout")):
                from handler import handle
                result = handle(make_event(evento_xlsx), None)

        # El archivo ya está en MinIO — retornamos 200 aunque el callback falle
        assert result["statusCode"] == 200
```

### 5.4 Prueba E2E con Testcontainers

```python
# tests/test_e2e_reporting.py
"""
E2E con Testcontainers MinIO:
- Levanta MinIO real en Docker
- Sube archivo .parquet al bucket
- Ejecuta el handler
- Verifica que los 3 formatos existen en MinIO output/
"""
import io
import json
import os
import pytest
import pandas as pd
from minio import Minio
from testcontainers.core.container import DockerContainer
from testcontainers.core.waiting_utils import wait_for_logs
from datetime import datetime
from types import SimpleNamespace


MINIO_ACCESS = "minioadmin"
MINIO_SECRET = "minioadmin"
MINIO_BUCKET = "controlstock-reports"


@pytest.fixture(scope="module")
def minio_container():
    container = (
        DockerContainer("minio/minio:RELEASE.2024-01-16T16-07-38Z")
        .with_env("MINIO_ROOT_USER", MINIO_ACCESS)
        .with_env("MINIO_ROOT_PASSWORD", MINIO_SECRET)
        .with_command("server /data")
        .with_exposed_ports(9000)
    )
    with container:
        wait_for_logs(container, "API:", timeout=30)
        yield container


@pytest.fixture(scope="module")
def minio_client(minio_container):
    port = minio_container.get_exposed_port(9000)
    client = Minio(
        f"localhost:{port}",
        access_key=MINIO_ACCESS,
        secret_key=MINIO_SECRET,
        secure=False,
    )
    if not client.bucket_exists(MINIO_BUCKET):
        client.make_bucket(MINIO_BUCKET)
    return client, port


@pytest.fixture(scope="module")
def parquet_en_minio(minio_client):
    client, _ = minio_client
    df = pd.DataFrame({
        "sku": ["SKU-E2E-001", "SKU-E2E-002"],
        "nombre": ["Prod E2E A", "Prod E2E B"],
        "stock": [999, 500],
        "ubicacion": ["Z1", "Z2"],
        "ultima_actualizacion": ["2026-06-13", "2026-06-13"],
    })
    buf = io.BytesIO()
    df.to_parquet(buf, index=False)
    parquet_bytes = buf.getvalue()
    path = "parquet/STOCK_ACTUAL/2026/06/e2e-req-001.parquet"
    client.put_object(MINIO_BUCKET, path, io.BytesIO(parquet_bytes), len(parquet_bytes))
    return path


@pytest.mark.integration
@pytest.mark.parametrize("formato,ext", [("XLSX", "xlsx"), ("CSV", "csv"), ("PDF", "pdf")])
def test_e2e_genera_formato_en_minio(minio_client, parquet_en_minio, formato, ext):
    client, port = minio_client

    os.environ.update({
        "MINIO_ENDPOINT": f"localhost:{port}",
        "MINIO_ACCESS_KEY": MINIO_ACCESS,
        "MINIO_SECRET_KEY": MINIO_SECRET,
        "MINIO_BUCKET_INPUT": MINIO_BUCKET,
        "REPORT_SERVICE_URL": "http://mock-report-service:8087",
        "KAFKA_BROKER": "",
    })

    evento = {
        "evento": "ReporteParquetGenerado",
        "reporteId": f"reporte-e2e-{formato.lower()}",
        "requestId": f"e2e-req-{formato.lower()}",
        "reportType": "STOCK_ACTUAL",
        "formatoDestino": formato,
        "parquetPath": parquet_en_minio,
        "generadoPor": "admin@controlstock.local",
        "timestamp": datetime.utcnow().isoformat(),
    }

    mock_event = SimpleNamespace(body=json.dumps(evento).encode())

    with pytest.MonkeyPatch().context() as mp:
        mp.setattr("handler.requests.post", lambda *a, **kw: SimpleNamespace(status_code=200, raise_for_status=lambda: None))
        import importlib
        import handler as h
        importlib.reload(h)
        result = h.handle(mock_event, None)

    assert result["statusCode"] == 200

    # Verificar que el archivo existe en MinIO
    expected_path = f"output/{ext}/e2e-req-{formato.lower()}.{ext}"
    obj = client.stat_object(MINIO_BUCKET, expected_path)
    assert obj.size > 0


@pytest.mark.integration
def test_e2e_minio_inaccesible_publica_error(minio_client):
    """Cuando MinIO no es accesible, el handler retorna 500 (no rompe el cluster)."""
    os.environ.update({
        "MINIO_ENDPOINT": "localhost:19999",  # puerto inexistente
        "MINIO_ACCESS_KEY": MINIO_ACCESS,
        "MINIO_SECRET_KEY": MINIO_SECRET,
        "REPORT_SERVICE_URL": "http://mock-report-service:8087",
        "KAFKA_BROKER": "",
    })

    evento = {
        "evento": "ReporteParquetGenerado",
        "reporteId": "reporte-fail-001",
        "requestId": "req-fail-001",
        "reportType": "STOCK_ACTUAL",
        "formatoDestino": "XLSX",
        "parquetPath": "parquet/STOCK_ACTUAL/2026/06/req-fail-001.parquet",
        "generadoPor": "admin",
        "timestamp": datetime.utcnow().isoformat(),
    }

    mock_event = SimpleNamespace(body=json.dumps(evento).encode())

    import importlib
    import handler as h
    importlib.reload(h)
    result = h.handle(mock_event, None)

    assert result["statusCode"] == 500
```

### 5.5 Ejecución de Pruebas

```bash
cd functions/report-format-consumer

# Instalar dependencias de prueba
pip install -r requirements.txt pytest pytest-cov testcontainers

# Ejecutar pruebas unitarias
pytest tests/ -v -m "not integration" --cov=. --cov-report=term-missing

# Ejecutar pruebas E2E (requiere Docker)
pytest tests/test_e2e_reporting.py -v -m integration

# Coverage mínimo esperado: 85%
pytest tests/ --cov=. --cov-fail-under=85
```

---

## 6. Despliegue en K3s (local y prod)

### 6.1 Despliegue Local

```bash
# 1. Crear secrets de MinIO en namespace openfaas-fn
export MINIO_ACCESS_KEY="controlstock"
export MINIO_SECRET_KEY="changeme_local"
bash scripts/create-minio-secrets.sh

# 2. Construir y pushear imagen al registry local
faas-cli build -f stack.yml
faas-cli push -f stack.yml

# 3. Desplegar función
faas-cli deploy -f stack.yml

# 4. Verificar que la función está registrada en el gateway
faas-cli list --gateway http://localhost:8080
# Esperado: report-format-consumer aparece en la lista

# 5. Verificar que el Kafka Connector detecta el topic annotation
kubectl logs -n openfaas -l app=kafka-connector --tail=50
# Esperado: "Subscribed to topic: controlstock.reporting.parquet-generado"
```

#### Verificar Escalado a Réplica al Llegar un Evento

```bash
# Publicar un evento de prueba manualmente
kubectl exec -n messaging kafka-kafka-0 -- kafka-console-producer.sh \
  --broker-list kafka-kafka-bootstrap.messaging.svc.cluster.local:9092 \
  --topic controlstock.reporting.parquet-generado << EOF
{"evento":"ReporteParquetGenerado","reporteId":"test-001","requestId":"req-test-001","reportType":"STOCK_ACTUAL","formatoDestino":"CSV","parquetPath":"parquet/STOCK_ACTUAL/2026/06/req-test-001.parquet","generadoPor":"admin","timestamp":"2026-06-13T12:00:00"}
EOF

# Verificar que el pod de la función se levanta en openfaas-fn
kubectl get pods -n openfaas-fn -w
# Esperado: report-format-consumer-* → Running (puede tardar ~30s desde cero)
```

### 6.2 Despliegue Producción

```bash
# 1. Actualizar registry en stack.yml (reemplazar <VPS_IP>:3000 por OCIR)
# stack.yml:
#   image: <OCIR_REGION>.ocir.io/<TENANCY>/<NAMESPACE>/report-format-consumer:${VERSION}

# 2. Login al registry de producción
docker login <OCIR_REGION>.ocir.io

# 3. Build, push y deploy con versión explícita
VERSION=$(git rev-parse --short HEAD)
faas-cli build -f stack.yml --build-arg VERSION=$VERSION
faas-cli push -f stack.yml
faas-cli deploy -f stack.yml

# 4. Verificar en K3s producción
kubectl get pods -n openfaas-fn --kubeconfig ~/.kube/config-controlstock-prod
```

### 6.3 Script `scripts/deploy.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

GATEWAY="${OPENFAAS_GATEWAY:-http://localhost:8080}"
STACK_FILE="stack.yml"
NAMESPACE="${OPENFAAS_NAMESPACE:-openfaas-fn}"

echo "==> Creando secrets de MinIO..."
bash scripts/create-minio-secrets.sh

echo "==> Construyendo imagen de la función..."
faas-cli build -f "$STACK_FILE"

echo "==> Pusheando imagen al registry..."
faas-cli push -f "$STACK_FILE"

echo "==> Desplegando función en gateway $GATEWAY..."
faas-cli deploy -f "$STACK_FILE" --gateway "$GATEWAY"

echo "==> Verificando deployment..."
faas-cli describe report-format-consumer --gateway "$GATEWAY"

echo "==> Deploy completado."
```

---

## 7. Integración con el Pipeline CI/CD

### 7.1 Estructura del Jenkinsfile para Functions

La función `report-format-consumer` se incluye en el mismo repositorio que `report-etl-service` o en un repositorio dedicado `controlstock-functions`. El pipeline se activa cuando hay cambios en `functions/report-format-consumer/**`.

```groovy
// Jenkinsfile — pipeline para functions/report-format-consumer
pipeline {
    agent { label 'k3s-builder' }

    environment {
        REGISTRY     = "<VPS_IP>:3000/controlstock"
        IMAGE_NAME   = "report-format-consumer"
        GATEWAY      = "http://gateway.openfaas.svc.cluster.local:8080"
        IMAGE_TAG    = "${env.GIT_COMMIT[0..7]}"
    }

    stages {

        stage('Lint & Unit Tests') {
            steps {
                dir('functions/report-format-consumer') {
                    sh 'pip install -r requirements.txt pytest pytest-cov'
                    sh 'pytest tests/ -v -m "not integration" --junitxml=reports/unit-tests.xml'
                }
            }
            post {
                always {
                    junit 'functions/report-format-consumer/reports/unit-tests.xml'
                }
            }
        }

        stage('Build Image') {
            steps {
                sh "faas-cli build -f stack.yml --build-arg VERSION=${IMAGE_TAG}"
            }
        }

        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'registry-creds',
                    usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS')]) {
                    sh "docker login ${REGISTRY} -u ${REG_USER} -p ${REG_PASS}"
                    sh "faas-cli push -f stack.yml"
                }
            }
        }

        stage('Deploy to K3s') {
            steps {
                withCredentials([file(credentialsId: 'kubeconfig-local', variable: 'KUBECONFIG')]) {
                    sh "faas-cli deploy -f stack.yml --gateway ${GATEWAY}"
                }
            }
        }

        stage('Integration Tests') {
            when { branch 'main' }
            steps {
                dir('functions/report-format-consumer') {
                    sh 'pytest tests/test_e2e_reporting.py -v -m integration --junitxml=reports/integration-tests.xml'
                }
            }
            post {
                always {
                    junit 'functions/report-format-consumer/reports/integration-tests.xml'
                }
            }
        }
    }

    post {
        failure {
            echo "Pipeline fallido para report-format-consumer — revisar logs"
        }
    }
}
```

### 7.2 Notas sobre Versionado

- `faas-cli` gestiona versiones de funciones a través del tag de imagen en `stack.yml`.
- **No se usa `bumpImageTag.sh`** — el tag se construye con `${GIT_COMMIT[0..7]}` en el Jenkinsfile.
- Para rollback: `faas-cli deploy -f stack.yml` con el tag anterior actualizado en `stack.yml`.

---

## 8. Criterios de Aceptación

### Deployment y Conectividad

- [ ] Función `report-format-consumer` deployada y visible en `openfaas-fn` namespace:
  ```bash
  kubectl get pods -n openfaas-fn -l faas_function=report-format-consumer
  # Esperado: Ready (puede estar en 0/0 si no hay eventos pendientes — escala a cero)
  ```
- [ ] Kafka Connector suscrito al topic `controlstock.reporting.parquet-generado`:
  ```bash
  kubectl logs -n openfaas -l app=kafka-connector | grep "parquet-generado"
  # Esperado: linea de subscripción exitosa
  ```
- [ ] Secret `minio-credentials` presente en namespace `openfaas-fn`:
  ```bash
  kubectl get secret minio-credentials -n openfaas-fn
  ```

### Generación de Formatos

- [ ] Conversión `.parquet` → **XLSX**: archivo válido, hoja "Reporte", todas las columnas del DataFrame presentes
- [ ] Conversión `.parquet` → **CSV**: archivo UTF-8, header correcto, todas las filas del DataFrame presentes
- [ ] Conversión `.parquet` → **PDF**: bytes inician con `%PDF`, tamaño > 1KB, datos de tabla incluidos
- [ ] Archivos generados en MinIO ruta `controlstock-reports/output/{xlsx|csv|pdf}/{requestId}.{ext}`:
  ```bash
  mc ls local/controlstock-reports/output/ --recursive
  ```

### Callback a report-service

- [ ] `POST /reports/{id}/completar` llamado exitosamente tras generar el archivo de salida
- [ ] `report-service` actualiza el estado del reporte a `COMPLETADO` en PostgreSQL:
  ```sql
  SELECT estado FROM reportes WHERE id = '<reporteId>';
  -- Esperado: COMPLETADO
  ```

### Manejo de Errores

- [ ] Si MinIO no es accesible al leer el `.parquet`:
  - Handler retorna HTTP 500
  - Evento `ReporteETLFallido` publicado en `controlstock.reporting.etl-fallido`
  - `report-service` actualiza estado a `FALLIDO`
- [ ] Si el callback a `report-service` falla (ConnectionError):
  - El archivo **ya fue escrito en MinIO** — respuesta es igualmente exitosa (200)
  - Warning logeado, no excepción fatal

### Pruebas

- [ ] `pytest tests/ -m "not integration"` pasa al 100% (0 failures)
- [ ] `pytest tests/test_e2e_reporting.py -m integration` pasa al 100% (requiere Docker)
- [ ] Coverage >= 85% del handler y converters:
  ```bash
  pytest tests/ -m "not integration" --cov=. --cov-fail-under=85
  ```

### CI/CD

- [ ] Pipeline Jenkins ejecuta lint, unit tests, build, push y deploy sin errores
- [ ] Integration tests pasan en stage `Integration Tests` del Jenkinsfile
- [ ] La función aparece con el tag correcto post-deploy:
  ```bash
  faas-cli describe report-format-consumer --gateway http://localhost:8080
  ```
