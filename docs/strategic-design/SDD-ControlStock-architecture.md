# Strategic Design Document — Estrategia Arquitectónica

**Proyecto:** ControlStock | Parte del conjunto SDD — etapa Strategic Design / Pre-Design del SDLC.
Documentos complementarios: `SDD-ControlStock-domain.md` · `SDD-ControlStock-security.md`

---

## 1. Drivers Arquitectónicos

### Atributos de Calidad Prioritarios

| Atributo | Prioridad | Meta / SLA | Justificación |
|----------|-----------|-----------|---------------|
| Disponibilidad | Alta | 99.9% medido mensualmente en producción | RNF-001; operación continua del negocio sin ventanas de inactividad en horario operativo |
| Latencia — consultas | Alta | p95 < 2 s (stock, Kardex, dashboard) | RNF-002; experiencia del Operador en tiempo real |
| Latencia — escrituras | Alta | p95 < 3 s (registro de movimientos) | RNF-002; registro de entradas, salidas y ajustes en tiempo real |
| Escalabilidad | Alta | 500 usuarios concurrentes sin degradación | RNF-003; crecimiento previsto hasta 300-500 usuarios en año 3 |
| Seguridad | Alta | Zero Trust; RBAC; TLS en todos los canales; auditoría inmutable | RNF-004, RNF-005, RNF-006; datos operativos críticos del negocio |
| Mantenibilidad | Alta | Arquitectura modular DDD + hexagonal; CI/CD desde el inicio | RNF-008; equipo de tamaño reducido; modificabilidad de módulos sin impacto global |
| Observabilidad | Alta | Métricas, logs estructurados y trazas distribuidas centralizadas | RNF-009; diagnóstico en producción; alertas proactivas de SLA |
| RTO | Alta | < 30 minutos | ADC sección 5; mantenimientos fuera de horario operativo |
| RPO | Alta | < 1 hora | ADC sección 5; respaldo diario de PostgreSQL y MongoDB |
| Generación de reportes | Media | ≤ 10 s para reportes complejos | RNF-002; reportes batch no compiten con operaciones de stock |

---

### Restricciones

- **Infraestructura exclusiva:** producción en VPS Oracle Cloud OCI (VM.Standard.A1.Flex, 4 OCPU / 24 GB, Ampere ARM); desarrollo en VM QEMU/KVM local. No se usan servicios gestionados de cloud público (sin RDS, DocumentDB, MSK). Toda la infraestructura corre en K3s nativo. [ADC secciones 3, 10, 11]
- **Stack tecnológico mandatorio:** definido íntegramente en los scripts del framework SDLC (`.claude/scripts/` y `.claude/templates/`). No se pueden incorporar tecnologías fuera del stack sin revisión y aprobación explícita. [ADC sección 2]
- **Gestión de secretos:** credenciales y API keys gestionadas exclusivamente a través de HashiCorp Vault KV v2 (`controlstock/<env>/<servicio>`). Prohibido commit de secretos en el repositorio. [ADC sección 11]
- **CI/CD obligatorio:** proceso de despliegue automatizado desde las etapas iniciales; despliegue manual a producción no permitido. [ADC sección 11; RNF-010]
- **Metodologías de desarrollo:** DDD + BDD + ATDD obligatorias. Todo código de dominio con separación clara entre dominio, aplicación e infraestructura. [SRS sección 8; ADC sección 11]
- **Auditoría inmutable:** el registro de auditoría es una restricción de negocio no negociable (RN-011); ningún usuario ni proceso del sistema puede modificar ni eliminar registros de auditoría.
- **Presupuesto open-source:** todo el stack es open-source; sin licencias de software comercial. [ADC sección 10]

---

### Cross-Cutting Concerns

- **Seguridad transversal:** validación JWT por Kong en cada petición entrante; RBAC aplicado en cada microservicio sobre los claims del JWT; TLS en todos los canales (Kong ingress, Traefik ingress, inter-servicio cuando aplique, Kafka Strimzi, llamadas externas).
- **Auditoría transversal:** todo evento de dominio relevante genera un `AuditRecord` inmutable consumido por `audit-service` desde Kafka.
- **Observabilidad distribuida:** OpenTelemetry Java Agent instrumentado en todos los microservicios backend; logs JSON estructurados (Logback + Loki + Promtail); métricas Prometheus (kube-prometheus-stack); trazas distribuidas Grafana Tempo (OTLP). Instrumentación mínima obligatoria: latencia por endpoint, tasa de errores, uso de recursos, alertas activas del sistema.
- **Gestión de secretos en runtime:** todos los microservicios leen secretos de Vault en startup y en operación vía `spring-cloud-vault-config`; rotación de secretos sin redeploy.
- **Manejo de errores y resiliencia:** Circuit Breaker en llamadas externas (`integration-service`, Camel); reintentos con backoff exponencial para notificaciones y proveedores externos; Dead Letter Topic en Kafka para eventos no procesables; alertas en Grafana ante superación de umbrales de error.
- **Consistencia de eventos:** Transactional Outbox garantiza at-least-once en la publicación de eventos de dominio desde PostgreSQL hacia Kafka.
- **Calidad de código:** SonarQube quality gate obligatorio antes del push de imagen; Trivy image scan y OWASP Dependency Check en cada pipeline CI; gitleaks en cada commit.

---

## 2. Decisiones Estratégicas

## DS-001 — Arquitectura de Microservicios con Diseño Hexagonal y Event-Driven

**Contexto:** El SRS requiere modularidad (RNF-008), escalabilidad horizontal independiente (RNF-003), trazabilidad distribuida (RNF-009) y extensibilidad de integraciones (RF-018, RF-019). El ADC define este estilo como mandatorio.

**Decisión:** Arquitectura de microservicios con diseño hexagonal (DDD) y comunicación event-driven mediante Kafka. [Decisión previa — no revisable]

**Justificación:** La arquitectura hexagonal garantiza separación clara entre dominio, aplicación e infraestructura. Los microservicios permiten escalar de forma independiente los componentes de mayor carga (especialmente `inventory-service` y `alert-service`). Kafka desacopla el motor de alertas del registro de movimientos, evitando que el volumen de alertas afecte la latencia de escritura de stock.

**Consecuencias:** Cada bounded context se implementa como un microservicio independiente con su propia base de datos (ver DS-003). La comunicación entre servicios ocurre vía REST síncrono (interno K3s) para consultas y vía Kafka asíncrono para eventos de dominio.

---

## DS-002 — CQRS: PostgreSQL 16 (Command Side) + MongoDB 7 (Query / Read Model)

**Contexto:** La carga de lectura del Kardex, dashboard de KPIs y reportería es significativamente mayor que la carga de escritura transaccional. Separar los modelos optimiza el rendimiento en ambas dimensiones.

**Decisión:** CQRS con PostgreSQL 16 como BD de escritura (transacciones ACID, Liquibase migrations) y MongoDB 7 como BD de lectura (documentos desnormalizados para Kardex, stock, movimientos, dashboard y reportería). [Decisión previa — no revisable]

**Justificación:** PostgreSQL garantiza integridad transaccional en las operaciones de escritura de stock. MongoDB permite proyecciones desnormalizadas que responden consultas de Kardex y dashboard sin JOINs costosos, cumpliendo el SLA de latencia p95 < 2 s para consultas (RNF-002).

**Consecuencias:** Consistencia eventual entre el command side (PostgreSQL) y el read model (MongoDB). El lag de sincronización es proporcional al throughput de Kafka. El diseño de UI debe considerar este lag. Ver DS-CQRS-1, DS-CQRS-2, DS-CQRS-3 para el detalle del patrón de proyección.

---

## DS-003 — Database-per-Service

**Contexto:** El estilo de microservicios (DS-001) requiere autonomía de datos para que cada servicio pueda evolucionar su esquema y desplegarse de forma independiente sin acoplamiento a otros servicios.

**Decisión:** Cada bounded context es propietario exclusivo de su base de datos. Ningún otro servicio accede directamente a la BD de otro contexto. La comunicación de datos entre contextos ocurre mediante eventos de dominio (Kafka asíncrono) o consultas REST al servicio propietario.

**Justificación:** La autonomía de datos es la garantía fundamental del aislamiento entre microservicios. Sin Database-per-Service, los microservicios se acoplan implícitamente a través del esquema de BD compartida, eliminando la capacidad de despliegue y evolución independiente.

**Consecuencias:** Ausencia de JOINs directos entre las BDs operacionales de diferentes contextos. Los datos que cruzan contextos requieren eventos o REST. El read model MongoDB (`controlstock_readmodel`) agrega proyecciones de múltiples contextos para uso de Reporting, pero cada proyección es escrita exclusivamente por el contexto propietario de esos datos.

Bases de datos asignadas por contexto:

| Bounded Context | Base de Datos (Command) | Base de Datos (Read Model) |
|----------------|------------------------|--------------------------|
| IAM (BC-01) | `controlstock_iam` (PostgreSQL) | — |
| Catalog (BC-02) | `controlstock_catalog` (PostgreSQL) | Colección `productos` en `controlstock_readmodel` (MongoDB) |
| Inventory (BC-03) | `controlstock_inventory` (PostgreSQL) | Colecciones `kardex`, `movimientos`, `stock` en `controlstock_readmodel` (MongoDB) |
| Adjustment (BC-04) | `controlstock_adjustment` (PostgreSQL) | — |
| Alert (BC-05) | `controlstock_alert` (PostgreSQL) | — |
| Supplier (BC-06) | `controlstock_supplier` (PostgreSQL) | Colección `proveedores` en `controlstock_readmodel` (MongoDB) |
| Reporting (BC-07) | `controlstock_reporting` (PostgreSQL) | MinIO bucket `controlstock-reports` |
| Audit (BC-08) | `controlstock_audit` (PostgreSQL, append-only) | — |
| Integration (BC-09) | `controlstock_integration` (PostgreSQL) | — |

---

## DS-004 — Autenticación y Autorización Centralizada: Keycloak + Kong Gateway

**Contexto:** El sistema requiere RBAC granular (RF-003), tokens con expiración y revocación (RNF-004) y autenticación en toda funcionalidad (RN-001).

**Decisión:** Keycloak (realm `controlstock`) como Identity Provider OIDC/OAuth 2.0. Kong API Gateway valida JWT RS256 en todas las peticiones antes de enrutar a los microservicios. [Decisión previa — no revisable]

**Justificación:** Centralizar la validación del JWT en Kong elimina la necesidad de replicar la lógica de autenticación en cada microservicio. Los microservicios confían en los claims pre-validados del JWT. Los endpoints internos (K3s service-to-service DNS) no pasan por Kong.

**Consecuencias:** Toda petición externa pasa por Kong (puerto 8000 del VPS). Los microservicios backend no están expuestos directamente. Kong aplica rate limiting global (200 req/min) y gestiona CORS.

---

## DS-005 — Capa de Integración Centralizada: `integration-service` con Apache Camel 4.10.2

**Contexto:** El SRS requiere integración con múltiples proveedores externos con protocolos heterogéneos (REST y archivo — RF-019) y con un servicio de notificaciones externo (RF-018). Cada proveedor puede tener contratos distintos.

**Decisión:** Centralizar toda la conectividad con sistemas externos en un microservicio dedicado `integration-service` que actúa como Anti-Corruption Layer (ACL) con Apache Camel 4.10.2. [Decisión previa — no revisable]

**Justificación:** Centralizar en `integration-service` garantiza gobierno central de credenciales (desde Vault), SLAs, manejo de reintentos y Circuit Breakers. Aísla el dominio de negocio de las particularidades y volatilidad de los contratos externos. Apache Camel EIP gestiona los protocolos `http`, `file` (FTP/SFTP) y `timer` (polling periódico) de forma homogénea.

**Consecuencias:** `integration-service` es el único componente que se comunica con sistemas externos. Actúa también como orquestador de saga (ver DS-006). Es un componente crítico de alta disponibilidad; su fallo bloquea notificaciones externas y reposición de inventario.

---

## DS-006 — Saga Orquestada con Narayana LRA en `integration-service`

**Contexto:** El flujo de reposición de inventario (Saga-01) y el flujo de ajuste con aprobación (Saga-02) abarcan múltiples bounded contexts y requieren consistencia con posibilidad de compensación.

**Decisión:** Saga con estilo de orquestación. El orquestador reside en `integration-service` (Camel Saga EIP + Narayana LRA coordinator en namespace `infra`). [Decisión previa — no revisable]

**Justificación:** La orquestación centraliza la visibilidad y el control del flujo transaccional, facilitando el debugging, el monitoreo de sagas en curso y la gestión de compensaciones. El `integration-service` ya es el ACL externo y el punto de coordinación natural para los flujos que involucran sistemas externos.

**Consecuencias:** El `integration-service` es el coordinador de todas las sagas distribuidas. Es un cuello de botella potencial y un punto único de fallo para los flujos de saga. Su alta disponibilidad (HPA en K3s) es crítica. Los ADRs técnicos definirán los timeouts y políticas de compensación de cada saga.

---

## DS-007 — Transactional Outbox + Kafka para Publicación de Eventos de Dominio

**Contexto:** La publicación de eventos de dominio (como `EntradaRegistrada`, `StockActualizado`) debe ser atómica con la operación de escritura en PostgreSQL. El envío directo a Kafka en la misma transacción no es posible con R2DBC reactivo.

**Decisión:** Cada microservicio escribe el evento en una tabla `outbox` de su propia BD PostgreSQL dentro de la misma transacción de negocio. Un proceso Outbox Relay (scheduled) lee de la tabla outbox y publica en Kafka. [Decisión previa — no revisable]

**Justificación:** El Transactional Outbox garantiza at-least-once: si la transacción de negocio falla, el evento nunca se escribe en outbox; si la publicación a Kafka falla, el relay reintenta. Elimina el riesgo de eventos perdidos o publicados sin la transacción correspondiente.

**Consecuencias:** Latencia adicional mínima entre la escritura en PostgreSQL y la publicación en Kafka (proporcional al intervalo del scheduled relay). El read model MongoDB tiene consistencia eventual respecto al command side PostgreSQL.

---

## DS-008 — ETL Spark Unificado para Reportería: `report-etl-service`

**Contexto:** El sistema requiere generación de reportes parametrizables exportables en múltiples formatos (RF-015, RF-016). El volumen estimado es ~50 K filas/mes para movimientos y ~100 K filas/mes para auditoría. El ADC declara Scala + Spark como stack mandatorio para la capa de reportería.

**Decisión:** Un único job Spark (`report-etl-service`, Scala 2.13 + Apache Spark 3.x) realiza la extracción desde el read model MongoDB (y desde `controlstock_audit` vía JDBC para reportes de auditoría), la validación de esquema con patrón Factory por `ReportType`, y la transformación. Genera un archivo `.parquet` almacenado en MinIO (`controlstock-reports`) y publica el evento `ReporteParquetGenerado` en Kafka. Es un **job batch ejecutado por schedule** (reportes periódicos) o disparado por evento Kafka on-demand (cuando el usuario solicita un reporte desde RF-015); **no es un servicio REST persistente**; no expone endpoints HTTP. [Decisión previa — no revisable]

**Justificación:** Un ETL unificado elimina la duplicación de lógica de extracción por tipo de reporte. El patrón Factory por `ReportType` centraliza la transformación en un único componente. Spark es adecuado para los volúmenes estimados y soporta lectura de MongoDB vía Spark MongoDB Connector.

**Consecuencias:** La latencia del reporte on-demand incluye el tiempo de bootstrap del job Spark (estimado 30-60 s para cold start en K3s). Para reportes programados (schedule), la latencia es proporcional al intervalo del schedule. El archivo Parquet en MinIO es el contrato entre el ETL y la capa de formatos (DS-009).

---

## DS-009 — Capa Serverless de Formatos: OpenFaaS `report-format-consumer`

**Contexto:** Una vez generado el Parquet por el ETL, se necesita convertir al formato final solicitado (XLS, CSV, PDF). La carga es event-driven y no justifica un servicio REST persistente.

**Decisión:** Una única función OpenFaaS (`report-format-consumer`, python3-http) invocada por el Kafka Connector de OpenFaaS cuando llega el evento `ReporteParquetGenerado`. Lee el `.parquet` desde MinIO, genera el archivo en el formato pedido (determinado directamente del campo `formatoDestino` del evento) y lo almacena en MinIO como archivo final. Desplegada via Helm (`openfaas/openfaas` + `openfaas/kafka-connector`) en K3s. [Decisión previa — no revisable]

**Justificación:** OpenFaaS es la plataforma serverless ya aprovisionada en el stack (sin funciones de cloud público). El modelo event-driven elimina el servidor persistente para conversión de archivos. El formato se determina del evento; sin lógica de enrutamiento adicional.

**Consecuencias:** Posible cold start de la función en períodos de inactividad. El Kafka Connector de OpenFaaS debe estar configurado y operativo. El tiempo de conversión de formato se adiciona al tiempo total de generación del reporte.

---

## DS-010 — Base de Datos Dedicada de Reportería: `controlstock_reporting`

**Contexto:** El catálogo de esquemas de reportes (`report_schema_catalog`) y los metadatos de solicitudes/archivos son datos propios del bounded context de Reporting. Deben residir en su propia BD (Database-per-Service).

**Decisión:** El bounded context de Reporting (BC-07) posee una BD PostgreSQL dedicada `controlstock_reporting` con tablas: `report_schema_catalog`, `report_requests`, `report_files`. Los archivos generados se almacenan en MinIO (`controlstock-reports`).

**Justificación:** Separar el catálogo de esquemas de las BDs operacionales garantiza que el contexto de Reporting evolucione de forma independiente. Los esquemas de reporte son datos del dominio de Reporting, no de los contextos que proveen los datos.

**Consecuencias:** Los archivos generados (Parquet, XLSX, CSV, PDF) residen en MinIO, no en la BD. La URL del archivo se almacena en `report_files`. El acceso a los archivos requiere autenticación y autorización RBAC.

---

## DS-CQRS-1 — Segregación Write / Read (Command / Query)

**Contexto:** La arquitectura CQRS (DS-002) requiere que los microservicios operacionales no expongan su BD de escritura para consultas de reportería o dashboard.

**Decisión:** Cada microservicio operacional escribe en su propia BD PostgreSQL (Database-per-Service, lado command). El estado que necesitan los reportes y el dashboard se publica como eventos de dominio en Kafka vía Transactional Outbox (DS-007). Ningún microservicio de Reporting ni de dashboard accede directamente a las BDs operacionales de los servicios de dominio.

**Justificación:** La separación evita que las consultas de reportería impacten el rendimiento de las operaciones de escritura transaccional de stock. Además, permite que el esquema de la BD de escritura evolucione sin impactar el read model.

**Consecuencias:** Los datos del read model reflejan el estado con un lag consistente con la latencia de Kafka + proyección. Para consultas que requieren datos en tiempo real estricto (ej. stock en una salida en curso), el command side (PostgreSQL) sigue siendo la fuente de verdad.

---

## DS-CQRS-2 — Proyección de Eventos hacia el Read Model MongoDB

**Contexto:** Los eventos de dominio publicados en Kafka deben materializarse en MongoDB como documentos desnormalizados para que el Kardex, el dashboard de KPIs y el ETL de reportería los consuman con baja latencia.

**Decisión:** Cada microservicio operacional incluye un Kafka consumer (projection consumer) que lee los eventos de dominio del propio contexto desde Kafka y materializa/actualiza los documentos correspondientes en MongoDB `controlstock_readmodel`. La proyección es responsabilidad del contexto que produce los datos:
- `inventory-service` proyecta colecciones `kardex`, `movimientos`, `stock`.
- `catalog-service` proyecta colección `productos`.
- `supplier-service` proyecta colección `proveedores`.

**Justificación:** La proyección distribuida alinea con Database-per-Service: cada servicio es propietario de su proyección en el read model. Evita un "projection-service" centralizado que requeriría conocer el esquema de todos los servicios.

**Consecuencias:** Consistencia eventual entre el command side PostgreSQL y el read model MongoDB. El lag es proporcional al throughput de Kafka (estimado sub-segundo en operación normal). El Kardex visible en el dashboard puede reflejar el estado con un margen de tiempo respecto al stock operacional.

---

## DS-CQRS-3 — ETL Lee Exclusivamente del Read Model MongoDB

**Contexto:** El `report-etl-service` (Spark) necesita acceder a los datos para generar reportes sin impactar las BDs operacionales.

**Decisión:** El `report-etl-service` lee exclusivamente de las colecciones en `controlstock_readmodel` (MongoDB) vía Spark MongoDB Connector. Para el reporte de auditoría, lee de `controlstock_audit` (PostgreSQL) vía JDBC, ya que los registros de auditoría no se proyectan en el read model (son append-only y accedidos ocasionalmente). Está **prohibido** que el ETL apunte directamente a las BDs operacionales de los microservicios de dominio.

**Justificación:** Aislar el ETL del command side PostgreSQL protege el rendimiento operacional. El read model MongoDB ya está optimizado para queries de lectura; el ETL no introduce carga sobre las BDs transaccionales.

**Consecuencias:** Los reportes reflejan el estado del read model al momento de la extracción. Para el reporte de auditoría, la consulta JDBC a `controlstock_audit` es la única excepción válida al patrón, justificada porque los datos de auditoría no están en el read model por diseño.

---

## 3. Riesgos y Tradeoffs

### Riesgos

| ID | Riesgo | Probabilidad | Impacto | Mitigación |
|----|--------|-------------|---------|-----------|
| R-001 | Alta complejidad operacional de 9+ microservicios para un equipo de tamaño aún no definido | Media | Alto | Los scaffolds del framework SDLC reducen la fricción de bootstrapping; ArgoCD GitOps simplifica el despliegue declarativo; el ADC prioriza tooling open-source maduro |
| R-002 | Consistencia eventual del read model MongoDB genera lecturas desactualizadas en dashboard o Kardex | Media | Medio | Diseño de UI que indique el momento de la última actualización del read model; SLA de consistencia máximo aceptable (< 1 s en operación normal); monitoreo del lag de Kafka |
| R-003 | Curva de aprendizaje de Scala + Apache Spark para el ETL de reportería | Media | Medio | Scaffold provisto (`scala_hexagonal_scaffold.py`); el rol de Spark debe asignarse a un perfil con experiencia en Scala/JVM; las pruebas ETL se validan con Testcontainers |
| R-004 | SLA del servicio externo de notificaciones (tercero) no garantizado; fallo bloquea alertas externas | Media | Alto | Diseño desacoplado: las alertas se registran en BD independientemente del éxito de la notificación externa; reintentos con backoff exponencial; Circuit Breaker en `integration-service` |
| R-005 | Recursos del VPS OCI A1.Flex (4 OCPU / 24 GB) insuficientes bajo picos de carga estacional (cierre mensual/anual) | Media | Alto | HPA en K3s para `inventory-service` y `alert-service`; monitoreo proactivo en Grafana con alertas de uso de CPU/memoria; evaluación de upgrade de shape OCI ante métricas de pico |
| R-006 | Dependencias entre bounded contexts en sagas aumentan la complejidad de pruebas de integración | Media | Medio | WireMock para mocking de proveedores externos; Testcontainers para PostgreSQL/MongoDB/Kafka en tests de integración; cobertura ATDD/BDD como criterio de definición de "done" |
| R-007 | Normativa local de protección de datos no verificada antes del go-live | Baja | Alto | ADC sección 7 indica revisión legal pendiente; bloquear go-live hasta confirmación legal; las prácticas actuales (Vault, RBAC, TLS, auditoría) alinean con ISO 27001 |

---

### Tradeoffs Aceptados

| Tradeoff | Ganancia | Costo Aceptado |
|----------|----------|----------------|
| CQRS (PostgreSQL command + MongoDB read model) | Rendimiento óptimo en consultas de Kardex y dashboard sin impactar la escritura transaccional; SLA de latencia p95 < 2 s para consultas | Consistencia eventual; complejidad de sincronización (Outbox → Kafka → MongoDB); lag visible en dashboard |
| Microservicios sobre monolito modular | Escalabilidad independiente por contexto (inventory, alert); autonomía de despliegue; alineación con bounded contexts DDD | Mayor complejidad operacional (9+ servicios, CI/CD por servicio); latencia de red inter-servicio; overhead de Kafka en el camino feliz |
| Saga orquestada (vs. coreografía) | Control centralizado y visibilidad del flujo transaccional; facilita debugging de compensaciones y monitoreo de sagas en curso | Acoplamiento al orquestador (`integration-service`); cuello de botella potencial en flujos de reposición; el `integration-service` es un punto crítico de alta disponibilidad |
| Database-per-Service | Autonomía de esquema e independencia de despliegue por servicio; evolución del esquema sin impacto en otros servicios | Sin JOINs directos entre BDs de contextos distintos; datos compartidos requieren eventos o REST; complejidad de consistencia entre contextos |
| ETL batch Spark (vs. streaming tiempo real) | Simplicidad operacional; schedule predecible; eliminación del contrato inter-MS para reportes; no requiere servidor REST persistente | Latencia de reporte (datos reflejan el estado al momento del último run); cold start del job Spark en solicitudes on-demand (estimado 30-60 s) |
| OpenFaaS serverless para formatos (vs. servicio REST dedicado) | Escalabilidad event-driven; sin servidor persistente para conversión de archivos; sin costo de recursos en reposo | Dependencia del Kafka Connector de OpenFaaS; posible cold start de la función; depuración más compleja en entorno serverless |
| VPS K3s self-hosted (vs. cloud gestionado) | Minimización de costos de infraestructura (OCI Always Free tier A1.Flex); control total del cluster; sin vendor lock-in | Mayor responsabilidad operacional de gestión del cluster K3s; sin auto-healing de nodo (un único nodo en MVP); capacidad de escala horizontal limitada al VPS |

---

## 4. Recomendación y Próximos Pasos

### Resumen Ejecutivo

ControlStock adopta una arquitectura de microservicios hexagonales con CQRS event-driven sobre un stack open-source completamente definido en el ADC. El dominio se organiza en 9 bounded contexts con separación estricta de responsabilidades y datos (Database-per-Service). Las sagas orquestadas por `integration-service` gestionan los flujos transaccionales distribuidos. El read model MongoDB es la fuente de datos para el ETL de reportería (Spark) y el dashboard, garantizando latencia de lectura p95 < 2 s. La seguridad se implementa mediante Zero Trust con Keycloak + Kong como punto único de validación de identidad.

Las decisiones estratégicas están alineadas con el ADC y no son revisables; el trabajo de la etapa de Diseño Técnico es profundizarlas en ADRs, definir los esquemas de eventos Kafka, las APIs REST internas y las estrategias de migración de datos iniciales.

---

### Validaciones Pendientes antes de Iniciar el Diseño Técnico

1. **Tamaño y perfiles del equipo de desarrollo:** impacta directamente la cadencia de entrega y la viabilidad de los 9 microservicios en paralelo. Definir antes de la planificación de sprints.
2. **Región OCI para producción:** confirmar `sa-saopaulo-1` (recomendada por proximidad a usuarios LATAM) o alternativa; impacta residencia de datos y latencia.
3. **Revisión legal de normativas locales de protección de datos:** pendiente según ADC sección 7; es bloqueador para el go-live.
4. **Confirmación del período de retención de Kardex:** coordinación con área legal/contable; mínimo 5 años, pero el valor exacto define la estrategia de archivado.
5. **Estrategia de migración de datos iniciales:** definir el script de carga desde hojas de cálculo existentes al catálogo inicial y stock de apertura.

---

### Próximos Pasos — Diseño Técnico

1. **ADRs por decisión estratégica:** formalizar un ADR técnico por cada DS-xxx con alternativas evaluadas, consecuencias técnicas detalladas y criterios de revisión.
2. **Definición de esquemas de eventos Kafka:** especificar el contrato de cada evento de dominio (JSON Schema o Avro); definir naming de topics y políticas de particionamiento.
3. **Diseño de APIs REST internas:** especificar los endpoints REST sincrónicos entre microservicios (especialmente `alert-service` → `integration-service` y `report-service` → `report-etl-service`).
4. **Estrategia de Liquibase por microservicio:** definir el path de changelogs por servicio y el proceso de ejecución pre-deploy vía `run-liquibase-migrations.sh`.
5. **Diseño del Outbox Relay:** definir la implementación del relay (scheduled, intervalo, política de retry, dead letter) compatible con R2DBC reactivo.
6. **Modelo de seguridad Vault:** definir la estructura de paths (`controlstock/<env>/<servicio>`), políticas de AppRole y rotación de secretos por servicio.
7. **Plan de observabilidad técnico:** definir dashboards Grafana, alertas Prometheus y políticas de retención de logs en Loki.

---

### Dependencias y Bloqueadores

| Ítem | Tipo | Estado |
|------|------|--------|
| Tamaño y perfiles del equipo de desarrollo | Dependencia organizacional | Por definir |
| Región OCI confirmada para producción | Decisión técnica-organizacional | Por definir (sa-saopaulo-1 recomendado) |
| Revisión legal de normativas de datos | Dependencia regulatoria | Pendiente — bloqueador de go-live |
| Período de retención de Kardex confirmado por área legal | Dependencia legal/contable | Pendiente |
| Disponibilidad del entorno de desarrollo (VM QEMU/KVM) | Infraestructura | Pendiente confirmación TI |

---

*Generado como parte del Strategic Design del SDLC — ControlStock.*
*Documentos complementarios: `SDD-ControlStock-domain.md` · `SDD-ControlStock-security.md`*
