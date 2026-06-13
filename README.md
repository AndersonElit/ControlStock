# ControlStock

Repositorio del proyecto de desarrollo de software para la gestión centralizada de inventario en el dominio Retail / Logística.

---

## Ciclo de Vida del Proyecto (SDLC)

### Pre-SDLC — Recopilación de Información `[completado]`

Recopilación y estructuración de la información de negocio necesaria para iniciar el proyecto.

| Artefacto | Ruta |
|-----------|------|
| Formato de entrada PID | `requerimiento/input-plan-pid.md` |

---

### Etapa 1 — Planeación `[completado]`

Definición del proyecto: alcance, objetivos, stakeholders, riesgos y viabilidad. Resultado formalizado en el Project Initiation Document (PID).

| Artefacto | Ruta |
|-----------|------|
| Project Initiation Document (PID) | `docs/planning/PID-ControlStock.md` |

---

### Etapa 2 — Análisis de Requerimientos `[pendiente]`

Levantamiento detallado de requerimientos funcionales y no funcionales. Generación del Software Requirements Specification (SRS).

| Artefacto | Ruta |
|-----------|------|
| Software Requirements Specification (SRS) | `docs/requirements/SRS-ControlStock.md` |

---

### Etapa 3 — Pre-Diseño Estratégico `[pendiente]`

Definición de la arquitectura de alto nivel, dominios de negocio y estrategia técnica del sistema.

| Artefacto | Ruta |
|-----------|------|
| Strategic Design Document (SDD) | `docs/strategic-design/` |

---

### Etapa 4 — Diseño Técnico `[pendiente]`

Diseño detallado de componentes, modelo de datos, APIs e integraciones.

| Artefacto | Ruta |
|-----------|------|
| Technical Design Document | `docs/design/` |

---

### Etapa 5 — Implementación `[pendiente]`

Desarrollo del sistema según el diseño aprobado. Plan de desarrollo e iteraciones.

| Artefacto | Ruta |
|-----------|------|
| Plan de Desarrollo | `docs/development/` |

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
│   └── planning/
│       └── PID-ControlStock.md     # Project Initiation Document (PID)
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
