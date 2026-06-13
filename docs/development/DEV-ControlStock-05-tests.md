# Etapa 5 — Pruebas de Integración

## Índice

1. [Objetivo](#1-objetivo)
2. [Prerrequisitos](#2-prerrequisitos)
3. [Pruebas de Integración](#3-pruebas-de-integración)
4. [Configuración del Ambiente de Pruebas de Integración](#4-configuración-del-ambiente-de-pruebas-de-integración)
5. [Criterios de Aceptación](#5-criterios-de-aceptación)

> **Nota:** Las pruebas QA (ATDD/BDD con Cucumber, E2E con Playwright + REST Assured, pruebas de carga y rendimiento con k6) están documentadas en `docs/testing/` y son generadas por el skill `/testing-plan`. Este documento cubre exclusivamente las pruebas de integración de desarrollo: verificación de contratos entre microservicios, infraestructura (Kafka, PostgreSQL, MongoDB) y sistemas externos simulados con WireMock.

---

## 1. Objetivo

Verificar que los microservicios de ControlStock interactúan correctamente entre sí y con la infraestructura (Kafka, PostgreSQL, MongoDB, sistemas externos vía WireMock) una vez que todos los componentes han sido implementados individualmente.

Las pruebas de integración validan:

- **Flujos Kafka:** que los eventos publicados por un servicio productor sean consumidos y procesados correctamente por el servicio consumidor correspondiente.
- **Contratos de sistemas externos:** que las rutas Apache Camel en `integration-service` manejen correctamente los escenarios de éxito, error HTTP y timeout para cada sistema externo.
- **Sagas distribuidas:** que los flujos Saga-01 (Reposición de Proveedor) y Saga-02 (Ajuste de Inventario) completen exitosamente su camino feliz y ejecuten compensaciones en el orden correcto ante fallos.
- **Consistencia transaccional:** que los eventos de dominio se publiquen exclusivamente mediante el patrón Outbox (no dual-write).
- **Seguridad perimetral:** que el token JWT emitido por Keycloak sea validado correctamente por Kong antes de llegar a los microservicios.
- **Pipeline de reportería:** que el flujo completo ETL → parquet → conversión de formatos → notificación opere end-to-end.

---

## 2. Prerrequisitos

### Estado del Cluster K3s

Todos los microservicios deben estar desplegados como pods en el cluster K3s local antes de ejecutar las pruebas de integración:

```bash
# Verificar que todos los pods están Running
kubectl get pods -A --kubeconfig ~/.kube/config-controlstock-local

# Resultado esperado por namespace:
# NAMESPACE    NAME                              READY   STATUS    RESTARTS
# apps         adjustment-service-*              1/1     Running   0
# apps         alert-service-*                   1/1     Running   0
# apps         audit-service-*                   1/1     Running   0
# apps         catalog-service-*                 1/1     Running   0
# apps         iam-service-*                     1/1     Running   0
# apps         integration-service-*             1/1     Running   0
# apps         inventory-service-*               1/1     Running   0
# apps         report-etl-service-*              1/1     Running   0
# apps         report-service-*                  1/1     Running   0
# apps         supplier-service-*                1/1     Running   0
# messaging    kafka-kafka-0                     1/1     Running   0
# messaging    kafka-zookeeper-0                 1/1     Running   0
# storage      minio-*                           1/1     Running   0
# openfaas-fn  report-format-consumer-*          1/1     Running   0  (o 0/0 escalado a cero)
```

### Infraestructura de Datos

```bash
# Verificar PostgreSQL accesible
kubectl exec -n storage deployment/postgresql -- psql -U controlstock_admin \
  -c "SELECT datname FROM pg_database WHERE datname LIKE 'controlstock%';"

# Verificar MongoDB accesible
kubectl exec -n storage deployment/mongodb -- mongosh \
  --eval "db.adminCommand({listDatabases:1}).databases.map(d=>d.name)"

# Verificar Kafka topics creados
kubectl exec -n messaging kafka-kafka-0 -- \
  kafka-topics.sh --bootstrap-server localhost:9092 --list | grep controlstock
```

### WireMock

```bash
# Verificar WireMock operativo y mappings cargados
curl http://<VPS_IP>:9999/__admin/mappings | jq '.mappings | length'
# Esperado: >= 1 mapping registrado

# Si WireMock no tiene mappings, cargarlos desde el directorio de fixtures:
curl -X POST http://<VPS_IP>:9999/__admin/mappings \
  -H "Content-Type: application/json" \
  -d @test-fixtures/wiremock/notificaciones-success.json
```

---

## 3. Pruebas de Integración

### 3.1 Matriz de Escenarios de Integración entre Servicios

| Escenario | Servicio productor | Servicio consumidor | Flujo | Herramienta |
|-----------|-------------------|---------------------|-------|-------------|
| Entrada registra → stock actualiza → alerta | inventory-service | alert-service | Kafka `StockActualizado` | Testcontainers + JUnit 5 |
| Alerta → notificación externa | alert-service | integration-service (WireMock) | REST interno K3s | WebTestClient + WireMock |
| Ajuste aprobado → stock aplicado (Saga-02) | adjustment-service | inventory-service | Kafka `AjusteAprobado` | Testcontainers |
| Reposición proveedor REST (Saga-01) | integration-service | inventory-service | WireMock proveedor | WireMock + WebTestClient |
| Producto creado → proyección MongoDB | catalog-service | MongoDB read model | Kafka + MongoDB | Testcontainers |
| Eventos → audit_log | all services | audit-service | Kafka | Testcontainers + Kafka |
| Token JWT → Kong → microservicio | Keycloak | inventory-service | Kong JWT validation | REST Assured |
| Reporte generado → formato creado | report-etl-service | report-format-consumer | Kafka + MinIO | Testcontainers MinIO |

### 3.2 Descripción de Escenarios Clave

#### Escenario 1: Entrada registra → stock actualiza → alerta

```
POST /inventory/entradas  →  inventory-service
  ├── Persiste entrada en PostgreSQL (controlstock_inventory)
  ├── Publica evento StockActualizado → Kafka
  └── alert-service consume StockActualizado
        ├── Evalúa reglas de alerta (stock mínimo/máximo)
        └── Si umbral superado → crea Alert en PostgreSQL (controlstock_alerts)
```

**Verificaciones:**
- La entrada aparece en `inventory_entries` con estado `REGISTRADO`
- El evento `StockActualizado` está en el topic Kafka (verificado vía Testcontainers Kafka consumer)
- Si el stock supera el umbral configurado, existe un registro en `alerts` con estado `PENDIENTE`

#### Escenario 2: Alerta → notificación externa

```
alert-service detecta umbral superado
  └── POST http://integration-service.apps.svc.cluster.local/notify
        └── integration-service → Apache Camel route → WireMock /notify
              ├── 200 → alert estado = ENVIADO
              ├── 503 → retry (3 intentos) → FALLIDO
              └── delay 12s → timeout → Circuit Breaker abre
```

**WireMock mappings requeridos:**
```json
// notificaciones-success.json
{
  "request": { "method": "POST", "url": "/notify" },
  "response": { "status": 200, "body": "{\"resultado\":\"ENVIADO\"}" }
}

// notificaciones-error.json
{
  "request": { "method": "POST", "url": "/notify" },
  "response": { "status": 503, "body": "Service Unavailable" }
}

// notificaciones-timeout.json
{
  "request": { "method": "POST", "url": "/notify" },
  "response": { "fixedDelayMilliseconds": 12000, "status": 200 }
}
```

#### Escenario 5: Producto creado → proyección MongoDB

```
POST /catalog/productos  →  catalog-service
  ├── Persiste en PostgreSQL (controlstock_catalog)
  ├── Publica evento ProductoCreado → Kafka
  └── Proyección actualiza colección MongoDB "products_view"
        └── Verificar: document con mismo SKU en MongoDB
```

#### Escenario 6: Eventos → audit_log (todos los servicios)

Verificar que cualquier operación de escritura en cualquier microservicio genera un evento Kafka que es consumido por `audit-service` y registrado en la tabla `audit_log` de PostgreSQL (`controlstock_audit`).

```java
// Ejemplo de test JUnit 5 + Testcontainers
@Test
void todaOperacionDeEscrituraGeneraRegistroEnAuditLog() {
    // Given: un producto creado en catalog-service
    webTestClient.post().uri("/catalog/productos")
        .bodyValue(new ProductoRequest("SKU-AUDIT-001", "Producto Audit Test"))
        .exchange()
        .expectStatus().isCreated();

    // When: esperar propagación Kafka → audit-service
    await().atMost(10, SECONDS).untilAsserted(() -> {
        // Then: verificar en audit_log
        Integer count = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM audit_log WHERE entidad = 'Producto' AND accion = 'CREAR' AND entidad_id = 'SKU-AUDIT-001'",
            Integer.class
        );
        assertThat(count).isEqualTo(1);
    });
}
```

#### Escenario 7: Token JWT → Kong → microservicio

```bash
# Obtener token de Keycloak para usuario operador_qa
TOKEN=$(curl -s -X POST \
  "http://<VPS_IP>:8180/realms/controlstock/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=controlstock-api&username=operador_qa@controlstock.local&password=Test1234!" \
  | jq -r '.access_token')

# Verificar que Kong valida el token antes de enrutar a inventory-service
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  http://<VPS_IP>:8000/inventory/stock
# Esperado: 200

# Verificar que sin token Kong rechaza con 401
curl -s -o /dev/null -w "%{http_code}" \
  http://<VPS_IP>:8000/inventory/stock
# Esperado: 401
```

### 3.3 Pruebas de Contrato — Sistemas Externos (integration-service)

Cada ruta Apache Camel en `integration-service` debe ser probada contra los tres escenarios siguientes con WireMock como simulador del sistema externo.

| Sistema externo | Ruta Camel | Escenario | Resultado esperado |
|----------------|-----------|-----------|-------------------|
| Servicio de Notificaciones | `POST /notify` | Éxito (HTTP 200) | `notification_logs.estado = ENVIADO` |
| Servicio de Notificaciones | `POST /notify` | Error HTTP (503) | `notification_logs.estado = FALLIDO`, 3 intentos de retry registrados |
| Servicio de Notificaciones | `POST /notify` | Timeout (delay 12s) | Circuit Breaker abre, `notification_logs.estado = FALLIDO`, CB estado `OPEN` en métricas |
| Proveedor REST | `POST /reposicion` | Éxito (HTTP 200) | Saga continúa al siguiente paso, `saga_instance.estado = EN_PROGRESO` |
| Proveedor REST | `POST /reposicion` | Error HTTP (500) | Saga inicia compensación, `saga_instance.estado = FALLIDO` |
| Proveedor REST | `POST /reposicion` | Timeout (delay 15s) | Saga inicia compensación por timeout, `saga_instance.estado = FALLIDO` |
| Proveedor FTP/SFTP | Upload SFTP stub | Upload OK | Archivo registrado en `integration_logs`, estado `TRANSFERIDO` |
| Proveedor FTP/SFTP | Upload SFTP stub | Auth failure | Error capturado, `integration_logs.estado = ERROR_AUTH`, sin reintento |

#### Ejemplo de test de contrato con WireMock + WebTestClient

```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@AutoConfigureWireMock(port = 9999)
class IntegrationServiceContractTest {

    @Autowired
    private WebTestClient webTestClient;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Test
    void notificacionExitosa_registraEnviado() {
        // Given: WireMock configurado para responder 200
        stubFor(post(urlEqualTo("/notify"))
            .willReturn(aResponse()
                .withStatus(200)
                .withBody("{\"resultado\":\"ENVIADO\"}")));

        // When
        webTestClient.post().uri("/integration/notificaciones")
            .bodyValue(new NotificacionRequest("alerta-001", "Stock bajo"))
            .exchange()
            .expectStatus().isOk();

        // Then
        await().atMost(5, SECONDS).untilAsserted(() -> {
            String estado = jdbcTemplate.queryForObject(
                "SELECT estado FROM notification_logs WHERE referencia_id = 'alerta-001'",
                String.class
            );
            assertThat(estado).isEqualTo("ENVIADO");
        });

        verify(1, postRequestedFor(urlEqualTo("/notify")));
    }

    @Test
    void notificacionTimeout_abreCircuitBreaker() {
        // Given: WireMock simula timeout (11s > timeout configurado de 10s)
        stubFor(post(urlEqualTo("/notify"))
            .willReturn(aResponse()
                .withFixedDelay(11000)
                .withStatus(200)));

        // When
        webTestClient.post().uri("/integration/notificaciones")
            .bodyValue(new NotificacionRequest("alerta-cb-001", "Test CB"))
            .exchange()
            .expectStatus().is5xxServerError();

        // Then: Circuit Breaker debe estar OPEN después del umbral
        // (verificar vía Actuator o métricas Micrometer)
        await().atMost(15, SECONDS).untilAsserted(() -> {
            var cbState = webTestClient.get()
                .uri("/actuator/health/circuitBreakers")
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

            assertThat(cbState).containsKey("notificacion-service");
        });
    }
}
```

### 3.4 Pruebas de Saga

#### Saga-01: Reposición de Proveedor (camino feliz)

```
POST /integration/reposiciones
  ├── Paso 1: integration-service → WireMock /reposicion → HTTP 200
  ├── Paso 2: inventory-service consume ReposicionAprobada → registra EntradaRegistrada
  └── Estado final: saga_instance.estado = COMPLETADO
```

**Verificaciones:**
```java
@Test
void saga01_caminoFeliz_completaSinErrores() {
    // Given
    stubFor(post(urlEqualTo("/reposicion"))
        .willReturn(aResponse().withStatus(200)
            .withBody("{\"ordenId\":\"ORD-PROV-001\"}")));

    // When
    String sagaId = webTestClient.post()
        .uri("/integration/reposiciones")
        .bodyValue(new ReposicionRequest("PROV-001", "SKU-001", 100))
        .exchange()
        .expectStatus().isAccepted()
        .returnResult(String.class)
        .getResponseBody()
        .blockFirst();

    // Then: esperar finalización de saga
    await().atMost(30, SECONDS).untilAsserted(() -> {
        String estado = jdbcTemplate.queryForObject(
            "SELECT estado FROM saga_instance WHERE id = ?", String.class, sagaId
        );
        assertThat(estado).isEqualTo("COMPLETADO");

        // Verificar log de pasos
        List<Map<String, Object>> pasos = jdbcTemplate.queryForList(
            "SELECT paso, estado FROM saga_step_log WHERE saga_id = ? ORDER BY orden", sagaId
        );
        assertThat(pasos).hasSize(2);
        assertThat(pasos.get(0)).containsEntry("estado", "COMPLETADO");
        assertThat(pasos.get(1)).containsEntry("estado", "COMPLETADO");

        // Verificar registro en integration_logs
        Integer logCount = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM integration_logs WHERE saga_id = ?", Integer.class, sagaId
        );
        assertThat(logCount).isGreaterThan(0);
    });
}
```

#### Saga-01: Fallo con compensación

```java
@Test
void saga01_falloEnPaso1_compensaEnOrdenInverso() {
    // Given: proveedor demora > timeout (15s)
    stubFor(post(urlEqualTo("/reposicion"))
        .willReturn(aResponse().withFixedDelay(16000).withStatus(200)));

    // When
    String sagaId = webTestClient.post()
        .uri("/integration/reposiciones")
        .bodyValue(new ReposicionRequest("PROV-002", "SKU-002", 50))
        .exchange()
        .expectStatus().isAccepted()
        .returnResult(String.class)
        .getResponseBody()
        .blockFirst();

    // Then: saga en FALLIDO, stock sin cambios
    await().atMost(40, SECONDS).untilAsserted(() -> {
        String estado = jdbcTemplate.queryForObject(
            "SELECT estado FROM saga_instance WHERE id = ?", String.class, sagaId
        );
        assertThat(estado).isEqualTo("FALLIDO");

        // Verificar orden inverso de compensación en saga_step_log
        List<Map<String, Object>> compensaciones = jdbcTemplate.queryForList(
            "SELECT paso, estado FROM saga_step_log WHERE saga_id = ? AND tipo = 'COMPENSACION' ORDER BY ejecutado_en",
            sagaId
        );
        // Las compensaciones deben ejecutarse en orden inverso a los pasos
        assertThat(compensaciones).allMatch(p -> "COMPENSADO".equals(p.get("estado")));

        // Stock no debe haber cambiado
        Integer stockActual = jdbcTemplate.queryForObject(
            "SELECT stock_disponible FROM stock WHERE sku = 'SKU-002'", Integer.class
        );
        assertThat(stockActual).isEqualTo(stockInicial("SKU-002"));
    });
}
```

#### Saga-02: Ajuste de Inventario (camino feliz)

```
POST /adjustments                          → adjustment-service crea ajuste en PENDIENTE
POST /adjustments/{id}/aprobar             → supervisor aprueba
  ├── adjustment-service publica AjusteAprobado → Kafka
  ├── inventory-service consume AjusteAprobado → aplica cambio de stock
  └── Estado final: ajuste en APROBADO, stock modificado
```

```java
@Test
void saga02_caminoFeliz_stockModificadoAtomicamente() {
    // Given: stock inicial conocido
    int stockInicial = jdbcTemplate.queryForObject(
        "SELECT stock_disponible FROM stock WHERE sku = 'SKU-ADJ-001'", Integer.class
    );
    int cantidadAjuste = 25;

    // When: crear y aprobar ajuste
    String ajusteId = crearAjuste("SKU-ADJ-001", cantidadAjuste, "INCREMENTO");
    aprobarAjuste(ajusteId, "supervisor_qa@controlstock.local");

    // Then
    await().atMost(15, SECONDS).untilAsserted(() -> {
        String estadoAjuste = jdbcTemplate.queryForObject(
            "SELECT estado FROM adjustments WHERE id = ?", String.class, ajusteId
        );
        assertThat(estadoAjuste).isEqualTo("APROBADO");

        Integer stockFinal = jdbcTemplate.queryForObject(
            "SELECT stock_disponible FROM stock WHERE sku = 'SKU-ADJ-001'", Integer.class
        );
        assertThat(stockFinal).isEqualTo(stockInicial + cantidadAjuste);
    });
}
```

#### Saga-02: Fallo en paso 3 — compensación al ajuste

```java
@Test
void saga02_falloEnInventory_revierteAjusteAEstadoError() {
    // Given: forzar error en inventory-service para este SKU específico
    // (usando feature flag o WireMock si inventory es externo)
    int stockInicial = obtenerStock("SKU-ADJ-ERR-001");

    String ajusteId = crearAjuste("SKU-ADJ-ERR-001", 10, "INCREMENTO");
    forzarErrorInventory("SKU-ADJ-ERR-001");  // configura el servicio para fallar
    aprobarAjuste(ajusteId, "supervisor_qa@controlstock.local");

    // Then: ajuste en ERROR, stock sin cambios
    await().atMost(20, SECONDS).untilAsserted(() -> {
        String estadoAjuste = jdbcTemplate.queryForObject(
            "SELECT estado FROM adjustments WHERE id = ?", String.class, ajusteId
        );
        assertThat(estadoAjuste).isEqualTo("ERROR");

        // Stock no debe haber cambiado
        assertThat(obtenerStock("SKU-ADJ-ERR-001")).isEqualTo(stockInicial);
    });
}
```

#### Idempotencia de Compensaciones

```java
@Test
void compensacion_idempotente_segundaLlamadaNoGeneraDuplicados() {
    // Given: saga en estado FALLIDO con compensación ya ejecutada
    String ajusteId = crearAjusteYFallar("SKU-IDEM-001");

    // When: llamar a compensar dos veces
    webTestClient.post()
        .uri("/adjustments/{id}/compensar", ajusteId)
        .exchange()
        .expectStatus().isOk();  // primera llamada

    webTestClient.post()
        .uri("/adjustments/{id}/compensar", ajusteId)
        .exchange()
        .expectStatus().isOk();  // segunda llamada — debe ser idempotente

    // Then: no hay duplicados en processed_message
    Integer count = jdbcTemplate.queryForObject(
        "SELECT COUNT(*) FROM processed_message WHERE saga_id = ? AND tipo = 'COMPENSACION'",
        Integer.class, ajusteId
    );
    assertThat(count).isEqualTo(1);  // solo un registro, no duplicado
}
```

---

## 4. Configuración del Ambiente de Pruebas de Integración

### 4.1 Variables de Entorno

```properties
# URL base a través de Kong Gateway
BASE_URL=http://<VPS_IP>:8000

# Keycloak
KEYCLOAK_URL=http://<VPS_IP>:8180/realms/controlstock
KEYCLOAK_CLIENT_ID=controlstock-api
KEYCLOAK_CLIENT_SECRET=<client_secret>

# Bases de datos (acceso directo para verificaciones)
POSTGRES_URL=jdbc:postgresql://<VPS_IP>:5432/controlstock_inventory
MONGODB_URL=mongodb://<VPS_IP>:27017

# WireMock
WIREMOCK_URL=http://<VPS_IP>:9999

# MinIO
MINIO_ENDPOINT=http://<VPS_IP>:9000
MINIO_ACCESS_KEY=controlstock
MINIO_SECRET_KEY=<minio_secret>
```

### 4.2 Usuarios QA en Keycloak

Los siguientes usuarios son creados automáticamente por el script de seed del realm Keycloak (`scripts/keycloak-seed.sh`):

| Usuario | Contraseña | Rol | Permisos |
|---------|-----------|-----|---------|
| `operador_qa@controlstock.local` | `Test1234!` | `OPERADOR` | Lectura de stock, registro de entradas/salidas |
| `supervisor_qa@controlstock.local` | `Test1234!` | `SUPERVISOR` | Aprobación de ajustes, reportes |
| `admin_qa@controlstock.local` | `Test1234!` | `ADMIN` | Administración completa |
| `gerente_qa@controlstock.local` | `Test1234!` | `GERENTE` | Acceso de lectura gerencial, reportes ejecutivos |
| `auditor_qa@controlstock.local` | `Test1234!` | `AUDITOR` | Acceso de solo lectura al audit_log |

```bash
# Verificar usuarios en Keycloak
curl -s "http://<VPS_IP>:8180/admin/realms/controlstock/users" \
  -H "Authorization: Bearer $(obtener_token_admin)" \
  | jq '.[].username'
```

### 4.3 Fixtures de Base de Datos

Antes de ejecutar las pruebas de integración se deben cargar los datos semilla correspondientes a cada bounded context:

```bash
# Cargar fixtures desde test-fixtures/db/
kubectl exec -n storage deployment/postgresql -- psql -U controlstock_admin << 'EOF'
-- Catalog
\c controlstock_catalog
INSERT INTO categories (id, nombre) VALUES ('cat-001', 'Electrónica'), ('cat-002', 'Ferretería')
  ON CONFLICT DO NOTHING;
INSERT INTO suppliers_catalog (id, nombre, codigo) VALUES ('sup-001', 'Proveedor Alpha', 'PROV-ALPHA')
  ON CONFLICT DO NOTHING;
INSERT INTO products (id, sku, nombre, categoria_id) VALUES
  ('prod-001', 'SKU-001', 'Producto Integración A', 'cat-001'),
  ('prod-002', 'SKU-002', 'Producto Integración B', 'cat-002'),
  ('prod-003', 'SKU-ADJ-001', 'Producto Ajuste Test', 'cat-001')
  ON CONFLICT DO NOTHING;

-- Inventory
\c controlstock_inventory
INSERT INTO stock (sku, stock_disponible, stock_minimo, stock_maximo, ubicacion)
VALUES
  ('SKU-001', 500, 50, 1000, 'A1'),
  ('SKU-002', 100, 20, 500, 'B2'),
  ('SKU-ADJ-001', 200, 10, 400, 'C3'),
  ('SKU-ADJ-ERR-001', 150, 10, 300, 'D4')
  ON CONFLICT DO NOTHING;

-- Alerts
\c controlstock_alerts
INSERT INTO alert_rules (sku, umbral_minimo, umbral_maximo, activa)
VALUES ('SKU-001', 50, 950, true)
  ON CONFLICT DO NOTHING;
EOF

echo "Fixtures cargados correctamente"
```

### 4.4 Verificación del Ambiente

```bash
#!/usr/bin/env bash
# scripts/verify-integration-env.sh
set -e

echo "=== Verificando ambiente de pruebas de integración ==="

# K3s pods
echo "[1/6] Pods en K3s..."
kubectl get pods -A --kubeconfig ~/.kube/config-controlstock-local \
  --field-selector=status.phase!=Running 2>/dev/null | grep -v "NAMESPACE" \
  && echo "ADVERTENCIA: hay pods no Running" || echo "OK - todos los pods Running"

# PostgreSQL
echo "[2/6] PostgreSQL..."
kubectl exec -n storage deployment/postgresql -- pg_isready -U controlstock_admin \
  && echo "OK" || echo "FALLO - PostgreSQL no disponible"

# MongoDB
echo "[3/6] MongoDB..."
kubectl exec -n storage deployment/mongodb -- mongosh --eval "db.runCommand({ping:1})" --quiet \
  && echo "OK" || echo "FALLO - MongoDB no disponible"

# Kafka
echo "[4/6] Kafka..."
kubectl exec -n messaging kafka-kafka-0 -- \
  kafka-topics.sh --bootstrap-server localhost:9092 --list > /dev/null \
  && echo "OK" || echo "FALLO - Kafka no disponible"

# WireMock
echo "[5/6] WireMock..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://<VPS_IP>:9999/__admin/mappings")
[ "$STATUS" = "200" ] && echo "OK" || echo "FALLO - WireMock no disponible (HTTP $STATUS)"

# MinIO
echo "[6/6] MinIO..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://<VPS_IP>:9000/minio/health/live")
[ "$STATUS" = "200" ] && echo "OK" || echo "FALLO - MinIO no disponible (HTTP $STATUS)"

echo "=== Verificación completada ==="
```

### 4.5 E2E del Pipeline de Reportería

#### (a) Camino feliz — generación completa de 3 formatos

```
Precondiciones:
  - MongoDB: colección "inventario_snapshot_2026_06" con >= 10 documentos
  - report-service: solicitud de reporte con ID "rep-e2e-001" en estado PENDIENTE
  - MinIO: bucket "controlstock-reports" con carpetas parquet/ y output/

Flujo:
  1. POST /reports/rep-e2e-001/generar  →  report-service
  2. report-service publica SolicitudReporteRecibida → Kafka
  3. report-etl-service consume evento → lee MongoDB → valida schema
  4. report-etl-service → escribe parquet en MinIO parquet/STOCK_ACTUAL/2026/06/rep-e2e-001.parquet
  5. report-etl-service publica ReporteParquetGenerado (XLSX) → Kafka
  6. report-etl-service publica ReporteParquetGenerado (CSV) → Kafka
  7. report-etl-service publica ReporteParquetGenerado (PDF) → Kafka
  8. report-format-consumer (×3) consume eventos → convierte → escribe en output/
  9. report-format-consumer (×3) → POST /reports/rep-e2e-001/completar
  10. report-service → estado = COMPLETADO

Verificaciones:
  - MinIO: output/xlsx/rep-e2e-001.xlsx → exists, size > 0
  - MinIO: output/csv/rep-e2e-001.csv → exists, size > 0
  - MinIO: output/pdf/rep-e2e-001.pdf → exists, size > 0
  - PostgreSQL (controlstock_reports): reportes.estado = 'COMPLETADO' WHERE id = 'rep-e2e-001'
```

```bash
# Verificar resultado del E2E de reportería
# 1. Verificar archivos en MinIO
mc ls local/controlstock-reports/output/ --recursive | grep "rep-e2e-001"
# Esperado: 3 líneas (xlsx, csv, pdf)

# 2. Verificar estado en PostgreSQL
kubectl exec -n storage deployment/postgresql -- psql -U controlstock_admin controlstock_reports \
  -c "SELECT id, estado, completado_en FROM reportes WHERE id = 'rep-e2e-001';"
# Esperado: estado = COMPLETADO, completado_en IS NOT NULL
```

#### (b) Fallo por validación — colección MongoDB incompleta

```
Precondiciones:
  - MongoDB: colección "inventario_snapshot_incompleto" sin campos requeridos ("sku", "stock")
  - report-service: solicitud de reporte con ID "rep-e2e-fail-001" en estado PENDIENTE

Flujo:
  1. POST /reports/rep-e2e-fail-001/generar  →  report-service
  2. report-etl-service lee MongoDB → falla validación de schema
  3. report-etl-service publica ReporteETLFallido → Kafka (controlstock.reporting.etl-fallido)
  4. report-service consume ReporteETLFallido → estado = FALLIDO

Verificaciones:
  - MinIO: NO existe parquet/STOCK_ACTUAL/2026/06/rep-e2e-fail-001.parquet
  - MinIO: NO existen archivos en output/ para rep-e2e-fail-001
  - PostgreSQL (controlstock_reports): reportes.estado = 'FALLIDO' WHERE id = 'rep-e2e-fail-001'
  - Kafka topic controlstock.reporting.etl-fallido: contiene evento con reporteId = 'rep-e2e-fail-001'
```

```bash
# Verificar ausencia de archivos parciales en MinIO
mc ls local/controlstock-reports/ --recursive | grep "rep-e2e-fail-001"
# Esperado: ninguna línea de salida (sin archivos parciales)

# Verificar estado FALLIDO en PostgreSQL
kubectl exec -n storage deployment/postgresql -- psql -U controlstock_admin controlstock_reports \
  -c "SELECT id, estado FROM reportes WHERE id = 'rep-e2e-fail-001';"
# Esperado: estado = FALLIDO
```

---

## 5. Criterios de Aceptación

### Integración entre Servicios

- [ ] Todos los escenarios de la **Matriz de Integración** (sección 3.1) pasan sin errores
- [ ] El evento `StockActualizado` publicado por `inventory-service` es consumido correctamente por `alert-service` y genera la alerta correspondiente cuando el umbral es superado
- [ ] La proyección MongoDB de `catalog-service` se actualiza dentro de los 5 segundos siguientes a la publicación del evento `ProductoCreado` en Kafka
- [ ] Todas las operaciones de escritura de todos los servicios generan un registro en `audit_log` (verificado con Testcontainers)

### Contratos con Sistemas Externos (WireMock)

- [ ] Las pruebas de contrato cubren los escenarios de **éxito, error HTTP y timeout** para cada ruta Camel registrada en `integration-service`
- [ ] El Circuit Breaker se abre tras el número configurado de timeouts consecutivos (verificado vía métricas Actuator)
- [ ] Los reintentos (retry) se ejecutan el número de veces configurado antes de marcar la notificación como `FALLIDO`
- [ ] El escenario de SFTP auth failure captura el error correctamente sin propagar una excepción no controlada

### Saga-01: Reposición de Proveedor

- [ ] **Camino feliz:** la saga completa todos los pasos y `saga_instance.estado = COMPLETADO`, con registro en `integration_logs`
- [ ] **Fallo:** ante timeout del proveedor, la compensación se ejecuta en **orden inverso** al avance de la saga (verificado en `saga_step_log.orden`)
- [ ] El stock no se modifica si la saga no completa todos sus pasos exitosamente

### Saga-02: Ajuste de Inventario

- [ ] **Camino feliz:** el ajuste aprobado modifica el stock de forma atómica (ambas operaciones en la misma transacción LRA o con consistencia eventual verificada)
- [ ] **Fallo en paso 3:** el ajuste revierte al estado `ERROR` y el stock permanece inalterado
- [ ] La compensación de la Saga-02 es **idempotente**: una segunda llamada a `POST /adjustments/{id}/compensar` retorna HTTP 200 sin crear registros duplicados en `processed_message`

### Outbox Pattern

- [ ] Los eventos de dominio se publican **exclusivamente mediante el patrón Outbox** (tabla `outbox_events`) — verificado con Testcontainers al validar que no hay escrituras directas al topic Kafka fuera del mecanismo de debezium/polling del Outbox
- [ ] No existen casos de dual-write (escritura directa al topic Kafka además del Outbox) en ningún microservicio

### Seguridad

- [ ] Kong rechaza peticiones sin token JWT con HTTP 401
- [ ] Kong rechaza peticiones con token expirado con HTTP 401
- [ ] Kong enruta correctamente peticiones con token válido para cada usuario QA (todos los roles verificados)

### CI/CD

- [ ] El stage `runIntegrationTests` del Jenkinsfile pasa exitosamente para **todos los microservicios**
- [ ] Los reportes JUnit XML se generan y son procesados correctamente por Jenkins

### Pipeline de Reportería E2E

- [ ] **Camino feliz:** el flujo completo ETL → parquet → 3 formatos genera los archivos correctos en MinIO `output/` y actualiza `report-service` a estado `COMPLETADO`
- [ ] **Fallo por validación:** la falla de schema en ETL publica `ReporteETLFallido`, no genera archivos parciales en MinIO y actualiza `report-service` a estado `FALLIDO`

---

> **Nota final:** Las pruebas QA (ATDD/BDD con Cucumber, E2E con Playwright + REST Assured, pruebas de carga y estrés con k6) están documentadas en `docs/testing/` y son producidas por el skill `/testing-plan`. Este documento se limita a las pruebas de integración ejecutadas por el equipo de desarrollo durante la etapa de implementación.
