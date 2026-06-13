-- ============================================================
-- ControlStock — Modelo de Datos — Artefacto de Diseño
-- Proyecto: ControlStock | Etapa: Diseño Técnico del SDLC
--
-- IMPORTANTE: Este archivo es el artefacto de diseño de referencia.
-- En producción NO existe un schema global compartido.
-- Cada bloque BC-XX corresponde al changelog Liquibase
-- `00001_initial_schema.yaml` del servicio propietario,
-- publicado en el repo `controlstock-migrations` en Gitea
-- (http://VPS_IP:3000/controlstock/controlstock-migrations)
-- y aplicado sobre su BD propia via run-liquibase-migrations.sh.
-- ============================================================

-- ============================================================
-- BC-01: IAM — controlstock_iam (iam-service)
-- ============================================================

CREATE TABLE roles (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre      VARCHAR(50) NOT NULL UNIQUE,
    descripcion VARCHAR(300),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE permisos (
    id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    modulo    VARCHAR(50) NOT NULL,
    operacion VARCHAR(50) NOT NULL,
    descripcion VARCHAR(200),
    UNIQUE (modulo, operacion)
);

CREATE TABLE rol_permisos (
    rol_id     UUID NOT NULL REFERENCES roles(id),
    permiso_id UUID NOT NULL REFERENCES permisos(id),
    PRIMARY KEY (rol_id, permiso_id)
);

CREATE TABLE usuarios (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    keycloak_sub      VARCHAR(200) NOT NULL UNIQUE,
    email             VARCHAR(200) NOT NULL UNIQUE,
    nombre            VARCHAR(200) NOT NULL,
    estado            VARCHAR(20)  NOT NULL DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO','INACTIVO')),
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE usuario_roles (
    usuario_id UUID NOT NULL REFERENCES usuarios(id),
    rol_id     UUID NOT NULL REFERENCES roles(id),
    PRIMARY KEY (usuario_id, rol_id)
);

CREATE INDEX idx_usuarios_email ON usuarios(email);
CREATE INDEX idx_usuarios_keycloak_sub ON usuarios(keycloak_sub);

-- ============================================================
-- BC-02: Catalog — controlstock_catalog (catalog-service)
-- ============================================================

CREATE TABLE categorias (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo      VARCHAR(20)  NOT NULL UNIQUE,
    nombre      VARCHAR(100) NOT NULL,
    descripcion VARCHAR(500),
    estado      VARCHAR(20)  NOT NULL DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO','INACTIVO')),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE productos (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo        VARCHAR(50)  NOT NULL UNIQUE,
    nombre        VARCHAR(200) NOT NULL,
    descripcion   VARCHAR(1000),
    categoria_id  UUID         NOT NULL REFERENCES categorias(id),
    stock_minimo  NUMERIC(12,3) NOT NULL DEFAULT 0 CHECK (stock_minimo >= 0),
    stock_maximo  NUMERIC(12,3) NOT NULL CHECK (stock_maximo > stock_minimo),
    estado        VARCHAR(20)  NOT NULL DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO','INACTIVO')),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_productos_categoria ON productos(categoria_id);
CREATE INDEX idx_productos_codigo ON productos(codigo);
CREATE INDEX idx_productos_estado ON productos(estado);

CREATE TABLE outbox (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id   UUID         NOT NULL,
    event_type     VARCHAR(100) NOT NULL,
    payload        JSONB        NOT NULL,
    topic          VARCHAR(200) NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    published_at   TIMESTAMPTZ,
    status         VARCHAR(20)  NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PUBLISHED','FAILED'))
);

CREATE INDEX idx_catalog_outbox_status_created ON outbox(status, created_at);

-- ============================================================
-- BC-03: Inventory — controlstock_inventory (inventory-service)
-- ============================================================

CREATE TABLE stock_levels (
    id          UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    producto_id UUID           NOT NULL UNIQUE,
    stock_actual NUMERIC(12,3) NOT NULL DEFAULT 0 CHECK (stock_actual >= 0),
    updated_at  TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    version     BIGINT         NOT NULL DEFAULT 0
);

CREATE INDEX idx_stock_levels_producto ON stock_levels(producto_id);

CREATE TABLE inventory_movements (
    id                   UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    producto_id          UUID           NOT NULL,
    tipo                 VARCHAR(20)    NOT NULL CHECK (tipo IN ('ENTRADA','SALIDA','AJUSTE')),
    cantidad             NUMERIC(12,3)  NOT NULL,
    referencia_documento VARCHAR(100)   NOT NULL,
    fecha                DATE           NOT NULL,
    saldo_resultante     NUMERIC(12,3)  NOT NULL,
    estado               VARCHAR(20)    NOT NULL DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO','ANULADO')),
    usuario_id           UUID           NOT NULL,
    saga_id              UUID,
    created_at           TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_movements_producto_fecha ON inventory_movements(producto_id, fecha DESC);
CREATE INDEX idx_movements_producto_created ON inventory_movements(producto_id, created_at DESC);
CREATE INDEX idx_movements_estado ON inventory_movements(estado);
CREATE INDEX idx_movements_saga ON inventory_movements(saga_id) WHERE saga_id IS NOT NULL;

-- Outbox para publicación atómica de eventos de dominio (Transactional Outbox)
CREATE TABLE outbox (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id   UUID         NOT NULL,
    event_type     VARCHAR(100) NOT NULL,
    payload        JSONB        NOT NULL,
    topic          VARCHAR(200) NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    published_at   TIMESTAMPTZ,
    status         VARCHAR(20)  NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PUBLISHED','FAILED'))
);

CREATE INDEX idx_inventory_outbox_status_created ON outbox(status, created_at);

-- Idempotencia para consumidores Kafka (Saga-02: AjusteAprobado)
CREATE TABLE processed_message (
    message_id   VARCHAR(200) PRIMARY KEY,
    consumer     VARCHAR(100) NOT NULL,
    processed_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ============================================================
-- BC-04: Adjustment — controlstock_adjustment (adjustment-service)
-- ============================================================

CREATE TABLE adjustment_requests (
    id                  UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    producto_id         UUID           NOT NULL,
    cantidad            NUMERIC(12,3)  NOT NULL CHECK (cantidad <> 0),
    motivo              VARCHAR(500)   NOT NULL CHECK (LENGTH(TRIM(motivo)) > 0),
    estado              VARCHAR(20)    NOT NULL DEFAULT 'PENDIENTE'
                            CHECK (estado IN ('PENDIENTE','APROBADO','RECHAZADO','ERROR')),
    usuario_solicitante UUID           NOT NULL,
    saga_id             UUID,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_adj_requests_estado ON adjustment_requests(estado);
CREATE INDEX idx_adj_requests_producto ON adjustment_requests(producto_id);

CREATE TABLE adjustment_decisions (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    adjustment_request_id UUID      NOT NULL REFERENCES adjustment_requests(id),
    decision            VARCHAR(20) NOT NULL CHECK (decision IN ('APROBADO','RECHAZADO')),
    comentario          VARCHAR(500),
    usuario_decisor     UUID        NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_adj_decisions_request ON adjustment_decisions(adjustment_request_id);

CREATE TABLE outbox (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id   UUID         NOT NULL,
    event_type     VARCHAR(100) NOT NULL,
    payload        JSONB        NOT NULL,
    topic          VARCHAR(200) NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    published_at   TIMESTAMPTZ,
    status         VARCHAR(20)  NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PUBLISHED','FAILED'))
);

CREATE INDEX idx_adjustment_outbox_status_created ON outbox(status, created_at);

CREATE TABLE processed_message (
    message_id   VARCHAR(200) PRIMARY KEY,
    consumer     VARCHAR(100) NOT NULL,
    processed_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ============================================================
-- BC-05: Alert — controlstock_alert (alert-service)
-- ============================================================

CREATE TABLE alert_rules (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    producto_id UUID        NOT NULL UNIQUE,
    activo      BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE alert_events (
    id           UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    producto_id  UUID           NOT NULL,
    tipo_alerta  VARCHAR(20)    NOT NULL CHECK (tipo_alerta IN ('BAJO_STOCK','SOBRESTOCK')),
    stock_actual NUMERIC(12,3)  NOT NULL,
    umbral       NUMERIC(12,3)  NOT NULL,
    estado       VARCHAR(20)    NOT NULL DEFAULT 'ACTIVA'
                     CHECK (estado IN ('ACTIVA','RECONOCIDA','RESUELTA')),
    created_at   TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_alert_events_producto ON alert_events(producto_id);
CREATE INDEX idx_alert_events_estado ON alert_events(estado);
CREATE INDEX idx_alert_events_tipo ON alert_events(tipo_alerta, estado);

-- ============================================================
-- BC-06: Supplier — controlstock_supplier (supplier-service)
-- ============================================================

CREATE TABLE suppliers (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre               VARCHAR(200) NOT NULL,
    identificacion_fiscal VARCHAR(50) NOT NULL UNIQUE,
    metodo_integracion   VARCHAR(20)  NOT NULL CHECK (metodo_integracion IN ('REST','ARCHIVO')),
    estado               VARCHAR(20)  NOT NULL DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO','INACTIVO')),
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE integration_configs (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id       UUID        NOT NULL UNIQUE REFERENCES suppliers(id),
    protocolo         VARCHAR(20) NOT NULL CHECK (protocolo IN ('REST','FTP','SFTP')),
    endpoint          VARCHAR(500),
    vault_secret_path VARCHAR(300) NOT NULL,
    configuracion_extra JSONB,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_suppliers_estado ON suppliers(estado);

-- ============================================================
-- BC-07: Reporting — controlstock_reporting (report-service)
-- ============================================================

CREATE TABLE report_schema_catalog (
    report_type      VARCHAR(50)  PRIMARY KEY,
    schema_version   INTEGER      NOT NULL DEFAULT 1,
    columns          JSONB        NOT NULL,
    integrity_rules  JSONB,
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE report_requests (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id  UUID        NOT NULL,
    report_type VARCHAR(50) NOT NULL REFERENCES report_schema_catalog(report_type),
    parametros  JSONB,
    formato     VARCHAR(10) NOT NULL CHECK (formato IN ('XLSX','CSV','PDF')),
    estado      VARCHAR(20) NOT NULL DEFAULT 'SOLICITADO'
                    CHECK (estado IN ('SOLICITADO','PROCESANDO','COMPLETADO','FALLIDO')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_report_requests_usuario ON report_requests(usuario_id);
CREATE INDEX idx_report_requests_estado ON report_requests(estado);

CREATE TABLE report_files (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    report_request_id UUID        NOT NULL REFERENCES report_requests(id),
    formato           VARCHAR(10) NOT NULL,
    url_minio         VARCHAR(500) NOT NULL,
    tamanio_bytes     BIGINT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_report_files_request ON report_files(report_request_id);

-- ============================================================
-- BC-08: Audit — controlstock_audit (audit-service)
-- Tabla append-only. Sin operaciones UPDATE/DELETE sobre registros existentes.
-- ============================================================

CREATE TABLE audit_log (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    entidad         VARCHAR(100) NOT NULL,
    entidad_id      UUID        NOT NULL,
    operacion       VARCHAR(50)  NOT NULL CHECK (operacion IN ('CREAR','MODIFICAR','INACTIVAR','MOVER','ANULAR','COMPENSAR')),
    usuario_id      UUID        NOT NULL,
    timestamp_utc   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valor_anterior  JSONB,
    valor_posterior JSONB,
    contexto        JSONB,
    evento_origen   VARCHAR(100)
);

CREATE INDEX idx_audit_log_entidad_id ON audit_log(entidad_id);
CREATE INDEX idx_audit_log_usuario ON audit_log(usuario_id);
CREATE INDEX idx_audit_log_timestamp ON audit_log(timestamp_utc DESC);
CREATE INDEX idx_audit_log_entidad_ts ON audit_log(entidad, timestamp_utc DESC);

-- ============================================================
-- BC-09: Integration — controlstock_integration (integration-service)
-- Incluye tablas de coordinador de saga (Saga-01 y Saga-02)
-- ============================================================

CREATE TABLE integration_logs (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo             VARCHAR(50)  NOT NULL,
    proveedor_id     UUID,
    request_payload  JSONB,
    response_payload JSONB,
    estado           VARCHAR(30)  NOT NULL,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_integration_logs_proveedor ON integration_logs(proveedor_id);
CREATE INDEX idx_integration_logs_estado ON integration_logs(estado);

CREATE TABLE notification_dispatch (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    alerta_id      UUID        NOT NULL,
    canal          VARCHAR(50) NOT NULL,
    contenido      JSONB       NOT NULL,
    estado         VARCHAR(30) NOT NULL DEFAULT 'PENDIENTE'
                       CHECK (estado IN ('PENDIENTE','ENVIADO','FALLIDO')),
    intentos       INTEGER     NOT NULL DEFAULT 0,
    ultimo_intento TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notification_dispatch_estado ON notification_dispatch(estado);

-- Tablas del coordinador de saga (Narayana LRA + Camel Saga EIP)
CREATE TABLE saga_instance (
    saga_id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_type     VARCHAR(100) NOT NULL,
    state         VARCHAR(50)  NOT NULL,
    current_step  INTEGER      NOT NULL DEFAULT 0,
    payload       JSONB        NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_saga_instance_type_state ON saga_instance(saga_type, state);

CREATE TABLE saga_step_log (
    id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_id               UUID         NOT NULL REFERENCES saga_instance(saga_id),
    step_name             VARCHAR(100) NOT NULL,
    status                VARCHAR(50)  NOT NULL,
    compensation_payload  JSONB,
    executed_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_saga_step_log_saga_id ON saga_step_log(saga_id);

-- Transactional Outbox del integration-service
CREATE TABLE outbox (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id   UUID         NOT NULL,
    event_type     VARCHAR(100) NOT NULL,
    payload        JSONB        NOT NULL,
    topic          VARCHAR(200) NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    published_at   TIMESTAMPTZ,
    status         VARCHAR(20)  NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PUBLISHED','FAILED'))
);

CREATE INDEX idx_integration_outbox_status_created ON outbox(status, created_at);

-- Idempotencia para consumidores Kafka
CREATE TABLE processed_message (
    message_id   VARCHAR(200) PRIMARY KEY,
    consumer     VARCHAR(100) NOT NULL,
    processed_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
