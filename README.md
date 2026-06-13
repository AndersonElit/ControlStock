# ControlStock

Repositorio del proyecto de desarrollo de software para la gestión centralizada de inventario en el dominio Retail / Logística.

---

## Etapa actual: Pre-SDLC — Planeación

El proyecto se encuentra en la etapa previa al ciclo de vida de desarrollo (SDLC). En esta fase se recopila, estructura y valida la información de negocio necesaria para iniciar formalmente la planeación del proyecto mediante un **Project Initiation Document (PID)**.

### Propósito de esta etapa

- Capturar los requerimientos de alto nivel del cliente.
- Estructurar la información del proyecto en un formato estándar.
- Proveer la entrada necesaria para generar el PID.
- Alinear a los stakeholders antes de iniciar el análisis de requerimientos.

---

## Estructura del repositorio

```
.
├── requerimiento/
│   └── input-plan-pid.md       # Formato de entrada diligenciado para /plan-pid
└── .claude/
    ├── formatos/
    │   └── input-template.md   # Plantilla base del formato de entrada
    └── skills/
        └── plan-pid/           # Skill que genera el PID a partir del formato de entrada
```

---

## Artefactos generados

| Artefacto | Ruta | Descripción |
|-----------|------|-------------|
| Formato de entrada PID | `requerimiento/input-plan-pid.md` | Información del cliente estructurada y lista para generar el PID |

---

## Flujo SDLC planificado

```
Pre-SDLC (actual)
    └── Recopilación de requerimientos del cliente
    └── Diligenciamiento del formato de entrada → requerimiento/input-plan-pid.md

Etapa 1 — Planeación
    └── Generación del PID (/plan-pid)
    └── Artefacto: docs/planning/PID-*.md

Etapa 2 — Análisis de Requerimientos
    └── Generación del SRS (/requirements-srs)
    └── Artefacto: docs/requirements/SRS-*.md

Etapa 3 — Pre-Diseño Estratégico
    └── Generación del Strategic Design SDD (/strategic-design-sdd)
    └── Artefacto: docs/strategic-design/

Etapa 4 — Diseño Técnico
    └── Generación del Technical Design SDD (/technical-design-sdd)
    └── Artefacto: docs/design/

Etapa 5 — Implementación
    └── Generación del Plan de Desarrollo (/development-plan)
    └── Artefacto: docs/development/

Etapa 6 — Pruebas
    └── Generación del Plan de Pruebas (/testing-plan)
    └── Artefacto: docs/testing/
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
