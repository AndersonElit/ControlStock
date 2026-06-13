# ControlStock

Repositorio del proyecto de desarrollo de software para la gestión centralizada de inventario en el dominio Retail / Logística.

---

## Ciclo de Vida del Proyecto (SDLC)

### Pre-SDLC — Recopilación de Información `[completado]`

Estructuración de la información de negocio necesaria para iniciar el proyecto. Se documentaron el contexto organizacional, los problemas operativos actuales y los objetivos de alto nivel que dieron origen a ControlStock.

| Artefacto | Ruta |
|-----------|------|
| Formato de entrada PID | `requerimiento/input-plan-pid.md` |

---

### Etapa 1 — Planeación `[completado]`

Formalización del proyecto mediante el Project Initiation Document (PID). Se definieron el alcance, los objetivos medibles, los stakeholders, los riesgos iniciales, la viabilidad técnica y económica, el cronograma de alto nivel y la estimación de costos (USD 80.000 – 150.000).

| Artefacto | Ruta |
|-----------|------|
| Project Initiation Document (PID) | `docs/planning/PID-ControlStock.md` |

---

### Etapa 2 — Análisis de Requerimientos `[completado]`

Especificación detallada del comportamiento esperado del sistema. El SRS documenta 20 requerimientos funcionales, 10 requerimientos no funcionales, 12 reglas de negocio, 8 casos de uso principales y criterios de aceptación verificables por requerimiento. Sirve como entrada directa para la etapa de diseño.

| Artefacto | Ruta |
|-----------|------|
| Software Requirements Specification (SRS) | `docs/requirements/SRS-ControlStock.md` |

---

### Etapa 3 — Pre-Diseño Estratégico `[completado]`

Definición de la arquitectura de alto nivel, dominios de negocio y estrategia técnica del sistema. Antes de ejecutar el diseño estratégico se diligencia el ADC (Architectural Decision Context), que consolida el stack tecnológico mandatorio, los drivers arquitectónicos, los atributos de calidad y las restricciones organizacionales. El ADC sirve como entrada enriquecida para la skill `/strategic-design-sdd` junto al SRS.

#### Paso previo — Architectural Decision Context (ADC) `[completado]`

Documento que captura el contexto tecnológico, infraestructura, estilo arquitectónico preferido, SLAs, compliance, integraciones y restricciones organizacionales del proyecto. Entrada requerida por `/strategic-design-sdd` para enriquecer las decisiones estratégicas.

| Artefacto | Ruta |
|-----------|------|
| Architectural Decision Context (ADC) | `docs/planning/ADC-ControlStock.md` |

#### Diseño estratégico `[completado]`

El SDD se compone de tres documentos complementarios generados a partir del SRS y el ADC. Establece los bounded contexts, el lenguaje ubicuo, los eventos de dominio, los flujos de saga, el modelo de seguridad y las decisiones arquitectónicas estratégicas que servirán de entrada al Diseño Técnico.

| Artefacto | Ruta |
|-----------|------|
| SDD — Dominio y Comportamiento | `docs/strategic-design/SDD-ControlStock-domain.md` |
| SDD — Seguridad | `docs/strategic-design/SDD-ControlStock-security.md` |
| SDD — Estrategia Arquitectónica | `docs/strategic-design/SDD-ControlStock-architecture.md` |

---

### Etapa 4 — Diseño Técnico `[completado]`

Diseño técnico completo del sistema a partir del Strategic Design. Define la arquitectura de microservicios hexagonales con CQRS event-driven, el stack tecnológico, los componentes por bounded context, las APIs REST, el modelo de datos polígota (PostgreSQL + MongoDB), los flujos de saga distribuida (Saga-01 reposición, Saga-02 ajuste), el diseño de seguridad técnica, la infraestructura K3s/Terraform y la matriz de trazabilidad ATDD. El conjunto de artefactos está listo como entrada para la etapa de Implementación.

| Artefacto | Ruta |
|-----------|------|
| SDD — Arquitectura del Sistema | `docs/design/SDD-ControlStock-system.md` |
| SDD — Diseño Técnico | `docs/design/SDD-ControlStock-design.md` |
| SDD — Infraestructura y Gobernanza | `docs/design/SDD-ControlStock-infrastructure.md` |
| Diagrama C4 Nivel 1 — Contexto | `docs/design/diagrams/SDD-ControlStock-c4-context.mmd` |
| Diagrama C4 Nivel 2 — Contenedores | `docs/design/diagrams/SDD-ControlStock-c4-container.mmd` |
| Especificación OpenAPI 3.0.3 | `docs/design/api/SDD-ControlStock-openapi.yaml` |
| Schema SQL — PostgreSQL (9 BDs) | `docs/design/database/SDD-ControlStock-schema.sql` |
| Colecciones MongoDB — Read Model | `docs/design/database/SDD-ControlStock-collections.js` |

---

### Etapa 5 — Implementación `[completado]`

Plan de desarrollo detallado a partir del Diseño Técnico. Define el roadmap maestro de 6 fases (infraestructura, bases de datos, scaffolding + CI/CD, microservicios, frontend, pruebas) con backlog de tareas, criterios de aceptación técnicos, dependencias y estimaciones por componente. Cubre los 10 microservicios hexagonales con CQRS event-driven, los 10 módulos frontend, la capa de observabilidad y el pipeline de reporting serverless.

| Artefacto | Ruta |
|-----------|------|
| Roadmap Maestro de Desarrollo | `docs/development/DEV-ControlStock-roadmap.md` |
| Etapa 00 — Infraestructura (K3s / Terraform) | `docs/development/DEV-ControlStock-00-infrastructure.md` |
| Etapa 01 — Bases de Datos (PostgreSQL + MongoDB) | `docs/development/DEV-ControlStock-01-databases.md` |
| Etapa 02 — Scaffolding de Microservicios | `docs/development/DEV-ControlStock-02-scaffold.md` |
| Etapa 02b — Pipeline CI/CD | `docs/development/DEV-ControlStock-02b-cicd.md` |
| MS — IAM Service | `docs/development/DEV-ControlStock-03-ms-iam-service.md` |
| MS — Catalog Service | `docs/development/DEV-ControlStock-03-ms-catalog-service.md` |
| MS — Inventory Service | `docs/development/DEV-ControlStock-03-ms-inventory-service.md` |
| MS — Adjustment Service | `docs/development/DEV-ControlStock-03-ms-adjustment-service.md` |
| MS — Alert Service | `docs/development/DEV-ControlStock-03-ms-alert-service.md` |
| MS — Supplier Service | `docs/development/DEV-ControlStock-03-ms-supplier-service.md` |
| MS — Integration Service | `docs/development/DEV-ControlStock-03-ms-integration-service.md` |
| MS — Report Service | `docs/development/DEV-ControlStock-03-ms-report-service.md` |
| MS — Report ETL Service | `docs/development/DEV-ControlStock-03-ms-report-etl-service.md` |
| MS — Audit Service | `docs/development/DEV-ControlStock-03-ms-audit-service.md` |
| FE — Autenticación | `docs/development/DEV-ControlStock-04-fe-auth.md` |
| FE — Dashboard Ejecutivo | `docs/development/DEV-ControlStock-04-fe-dashboard.md` |
| FE — Catálogo de Productos | `docs/development/DEV-ControlStock-04-fe-catalogo.md` |
| FE — Inventario y Kardex | `docs/development/DEV-ControlStock-04-fe-inventario.md` |
| FE — Ajustes de Stock | `docs/development/DEV-ControlStock-04-fe-ajustes.md` |
| FE — Alertas y Notificaciones | `docs/development/DEV-ControlStock-04-fe-alertas.md` |
| FE — Gestión de Proveedores | `docs/development/DEV-ControlStock-04-fe-proveedores.md` |
| FE — Reportes | `docs/development/DEV-ControlStock-04-fe-reportes.md` |
| FE — Administración y Roles | `docs/development/DEV-ControlStock-04-fe-administracion.md` |
| FE — Auditoría | `docs/development/DEV-ControlStock-04-fe-auditoria.md` |
| Etapa 05 — Plan de Pruebas Integrado | `docs/development/DEV-ControlStock-05-tests.md` |
| Etapa 06 — Reporting Serverless | `docs/development/DEV-ControlStock-06-reporting-serverless.md` |
| Observabilidad (Prometheus / Grafana / Jaeger) | `docs/development/DEV-ControlStock-0c-observability.md` |

---

### Etapa 6 — Pruebas `[pendiente]`

Verificación funcional, de carga, seguridad y aceptación del sistema.

| Artefacto | Ruta |
|-----------|------|
| Plan de Pruebas | `docs/testing/` |

---

## Estructura del repositorio

```
.
├── requerimiento/
│   └── input-plan-pid.md           # Formato de entrada diligenciado para /plan-pid
├── docs/
│   ├── planning/
│   │   ├── PID-ControlStock.md          # Project Initiation Document (PID)
│   │   └── ADC-ControlStock.md          # Architectural Decision Context (ADC)
│   ├── requirements/
│   │   └── SRS-ControlStock.md          # Software Requirements Specification (SRS)
│   ├── strategic-design/
│   │   ├── SDD-ControlStock-domain.md        # Strategic Design — Dominio y Comportamiento
│   │   ├── SDD-ControlStock-security.md      # Strategic Design — Seguridad
│   │   └── SDD-ControlStock-architecture.md  # Strategic Design — Estrategia Arquitectónica
│   ├── design/
│   │   ├── SDD-ControlStock-system.md        # Technical Design — Arquitectura del Sistema
│   │   ├── SDD-ControlStock-design.md        # Technical Design — Diseño Técnico
│   │   ├── SDD-ControlStock-infrastructure.md # Technical Design — Infraestructura y Gobernanza
│   │   ├── diagrams/
│   │   │   ├── SDD-ControlStock-c4-context.mmd   # C4 Nivel 1 — Contexto (Mermaid)
│   │   │   └── SDD-ControlStock-c4-container.mmd # C4 Nivel 2 — Contenedores (Mermaid)
│   │   ├── api/
│   │   │   └── SDD-ControlStock-openapi.yaml     # Especificación OpenAPI 3.0.3
│   │   └── database/
│   │       ├── SDD-ControlStock-schema.sql        # DDL PostgreSQL — 9 bounded contexts
│   │       └── SDD-ControlStock-collections.js    # Colecciones MongoDB — Read Model CQRS
│   └── development/
│       ├── DEV-ControlStock-roadmap.md            # Roadmap maestro de desarrollo (6 fases)
│       ├── DEV-ControlStock-00-infrastructure.md  # Fase 00: Infraestructura K3s/Terraform
│       ├── DEV-ControlStock-01-databases.md       # Fase 01: Bases de datos PostgreSQL + MongoDB
│       ├── DEV-ControlStock-02-scaffold.md        # Fase 02: Scaffolding microservicios
│       ├── DEV-ControlStock-02b-cicd.md           # Fase 02b: Pipeline CI/CD
│       ├── DEV-ControlStock-03-ms-*.md            # Fase 03: 10 microservicios hexagonales
│       ├── DEV-ControlStock-04-fe-*.md            # Fase 04: 10 módulos frontend
│       ├── DEV-ControlStock-05-tests.md           # Fase 05: Plan de pruebas integrado
│       ├── DEV-ControlStock-06-reporting-serverless.md # Fase 06: Reporting serverless
│       └── DEV-ControlStock-0c-observability.md   # Observabilidad (Prometheus/Grafana/Jaeger)
└── .claude/
    ├── formatos/
    │   └── input-template.md       # Plantilla base del formato de entrada
    └── skills/
        └── plan-pid/               # Skill que genera el PID a partir del formato de entrada
```

---

## Resumen del proyecto

| Campo | Valor |
|-------|-------|
| Nombre | ControlStock |
| Tipo | Nuevo desarrollo |
| Dominio | Retail / Gestión de Inventario y Logística |
| Sponsor | Gerencia General |
| Duración estimada | 6 meses |
| Presupuesto estimado | USD 80.000 – USD 150.000 |

### Problema central

La organización gestiona su inventario con procesos manuales y herramientas dispersas (hojas de cálculo, registros físicos, aplicaciones no integradas), lo que genera falta de visibilidad en tiempo real, errores operativos, ausencia de trazabilidad y pérdidas económicas por faltantes o excesos de stock.

### Objetivo general

Implementar un sistema centralizado de gestión de inventario que controle existencias en tiempo real, registre movimientos, automatice el abastecimiento e integre servicios externos para apoyar la toma de decisiones.

### Alcance principal

- Administración de productos, categorías y proveedores.
- Control de stock mínimo/máximo con alertas automáticas.
- Registro de entradas y salidas (Kardex).
- Dashboard ejecutivo y reportería exportable.
- Integración con proveedores y servicios de notificación via API.
- Exposición de APIs para sistemas externos.
- Gestión de usuarios, roles y auditoría.
