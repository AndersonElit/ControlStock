# Project Initiation Document (PID)

**Proyecto:** ControlStock
**Fecha:** 2026-06-12
**Estado:** Borrador — Pendiente de aprobación

---

## 1. Resumen Ejecutivo

ControlStock es un sistema centralizado de gestión de inventario diseñado para reemplazar los procesos manuales y herramientas dispersas que actualmente operan en la organización. El proyecto busca eliminar las inconsistencias de información, la falta de trazabilidad y los costos operativos asociados al control manual de existencias.

El sistema proveerá visibilidad en tiempo real del inventario, automatizará alertas y procesos de abastecimiento, integrará fuentes de datos con proveedores externos y generará información confiable para la toma de decisiones en todos los niveles de la organización.

La viabilidad técnica, operacional y económica del proyecto es favorable. Se recomienda aprobación e inicio inmediato de la etapa de Análisis de Requerimientos.

---

## 2. Descripción General del Proyecto

| Campo                  | Detalle                                          |
|------------------------|--------------------------------------------------|
| **Nombre del proyecto**| ControlStock                                     |
| **Tipo de proyecto**   | Nuevo desarrollo                                 |
| **Dominio de negocio** | Retail / Gestión de Inventario y Logística       |
| **Sponsor**            | Gerencia General                                 |
| **Project Manager**    | Por definir                                      |
| **Duración estimada**  | 6 meses                                          |
| **Fecha de inicio**    | Por definir tras aprobación del PID              |
| **Metodología**        | Ágil (Scrum) con prácticas DDD, BDD y ATDD       |

---

## 3. Problema de Negocio

### Situación Actual

La organización gestiona su inventario mediante procesos manuales, hojas de cálculo, registros físicos y aplicaciones no integradas. Esta fragmentación impide la visibilidad en tiempo real de las existencias y genera inconsistencias sistemáticas en la información operativa.

### Problemas Operacionales

- Ausencia de control centralizado del inventario.
- Sin trazabilidad de movimientos de entrada y salida de productos.
- Identificación tardía de productos con stock bajo o agotado.
- Errores recurrentes en registros manuales de inventario.
- Generación manual de reportes operativos y gerenciales, con alto costo de tiempo.
- Procesos de reposición no automatizados, sujetos a criterios subjetivos.
- Sin integración con proveedores ni sistemas de notificación automatizados.

### Impacto en el Negocio

- Pérdidas económicas por faltantes o sobrestock de productos.
- Retrasos en los procesos de abastecimiento y reposición.
- Capacidad limitada de planificación y toma de decisiones basada en datos.
- Incremento de costos operativos por reprocesos y correcciones manuales.
- Deterioro de la satisfacción de clientes internos y externos por quiebres de stock.

---

## 4. Objetivos del Proyecto

### Objetivo General

Implementar un sistema centralizado de gestión de inventario que permita administrar productos, controlar existencias en tiempo real, registrar movimientos, automatizar procesos de abastecimiento y generar información confiable para la toma de decisiones.

### Objetivos Específicos

- Centralizar la administración de productos, categorías y existencias en una única plataforma.
- Automatizar el registro y seguimiento de todos los movimientos de inventario (entradas, salidas, ajustes).
- Implementar alertas automáticas configurables para control de stock mínimo y máximo.
- Integrar el sistema con servicios externos de notificación y proveedores mediante APIs estándar.
- Generar reportes operativos, tácticos y estratégicos exportables con indicadores clave de inventario.
- Garantizar trazabilidad y auditoría completa de todas las operaciones del sistema.
- Reducir los errores de inventario en al menos un 80% respecto al proceso manual actual.
- Reducir el tiempo de generación de reportes gerenciales en al menos un 70%.

---

## 5. Alcance

### Incluido en el Alcance

- Administración del catálogo de productos y categorías.
- Gestión de stock y existencias en tiempo real.
- Registro de movimientos de entrada, salida y ajuste de inventario.
- Consulta de historial de movimientos por producto (Kardex).
- Gestión de proveedores y sus datos de contacto e integración.
- Control configurable de stock mínimo y máximo por producto.
- Alertas automáticas de inventario (bajo stock, sobrestock, vencimientos).
- Dashboard ejecutivo con KPIs de inventario.
- Reportería operativa y gerencial exportable.
- Auditoría completa de operaciones del sistema.
- Integración con servicios de notificaciones (email, mensajería).
- Integración con proveedores mediante APIs REST o intercambio de archivos.
- Exposición de APIs para consulta y actualización de inventario desde sistemas externos.
- Gestión de usuarios, roles y permisos (RBAC).

### Fuera del Alcance

- Implementación de sistemas contables o financieros.
- Gestión de recursos humanos o nómina.
- Facturación electrónica.
- Módulos CRM.
- Aplicaciones móviles nativas (diferidas para fases posteriores).
- Implementación de módulos ERP.
- Integración con plataformas de e-commerce (planificada para fases futuras).

---

## 6. Stakeholders

| Stakeholder              | Rol                       | Responsabilidad                                           |
|--------------------------|---------------------------|-----------------------------------------------------------|
| Gerencia General         | Sponsor                   | Aprobar presupuesto, objetivos estratégicos y el PID      |
| Project Manager          | Gestión del proyecto      | Planificación, seguimiento, coordinación y comunicación   |
| Supervisor de Inventario | Usuario clave             | Validar procesos operativos y requerimientos funcionales  |
| Operadores de Inventario | Usuario final             | Registro diario de movimientos y gestión operativa        |
| Área de Compras          | Usuario de negocio        | Validar flujos de abastecimiento y gestión de proveedores |
| Área de TI               | Soporte técnico           | Infraestructura, seguridad, integración y operación       |
| Proveedores Externos     | Integración externa       | Intercambio de información y mecanismos de integración    |
| Gerencia Comercial       | Consumidor de información | Análisis de reportes, KPIs e indicadores estratégicos     |

---

## 7. Requerimientos de Alto Nivel

### Requerimientos Funcionales

- Gestión completa del catálogo de productos (alta, baja, modificación, categorización).
- Administración de existencias y stock disponible por producto y ubicación.
- Registro de movimientos de inventario: entradas, salidas y ajustes.
- Consulta de historial de movimientos (Kardex) por producto y período.
- Gestión de proveedores con datos de contacto e integración.
- Configuración de alertas automáticas por stock mínimo, máximo y vencimiento.
- Dashboard ejecutivo con indicadores clave de inventario en tiempo real.
- Generación y exportación de reportes operativos y gerenciales.
- Integración con servicios externos de notificación (email, mensajería).
- Integración con proveedores para actualización de disponibilidad y pedidos.
- Exposición de APIs REST para integración con sistemas externos.
- Gestión de usuarios, roles y permisos basada en RBAC.
- Registro de auditoría con trazabilidad de todas las operaciones.

### Requerimientos No Funcionales

- Disponibilidad mínima del 99,9% (SLA).
- Autenticación y autorización basada en roles (RBAC).
- Comunicación segura mediante HTTPS/TLS en todos los canales.
- Trazabilidad completa de operaciones mediante logs de auditoría.
- Soporte para al menos 500 usuarios concurrentes.
- Tiempo de respuesta inferior a 2 segundos para consultas de inventario.
- Arquitectura escalable, modular y orientada a servicios.
- Observabilidad centralizada: métricas, logs y trazabilidad distribuida.
- Cumplimiento de políticas de seguridad corporativas.
- Despliegue sobre infraestructura cloud definida por la organización.

---

## 8. Supuestos y Restricciones

### Supuestos

- Los proveedores disponen de mecanismos tecnológicos para integración (APIs o intercambio de archivos).
- Los usuarios recibirán capacitación formal antes del despliegue a producción.
- La infraestructura tecnológica cloud estará disponible y operativa durante el desarrollo.
- Existe conectividad permanente y estable con los servicios externos requeridos.
- La organización designará un Project Manager antes del inicio formal del proyecto.
- Los datos iniciales de inventario podrán migrarse desde las fuentes actuales.

### Restricciones

- El sistema deberá desarrollarse como aplicación web responsive (sin app móvil nativa en fase 1).
- La integración con sistemas externos utilizará estándares abiertos (REST APIs, JSON).
- La solución debe cumplir con las políticas de seguridad corporativas vigentes.
- La solución operará sobre la infraestructura cloud definida por la organización.
- El proyecto deberá ejecutarse dentro del presupuesto aprobado sin exceder el rango definido.
- El ciclo de desarrollo seguirá prácticas de DDD, BDD, ATDD y CI/CD.

---

## 9. Análisis de Viabilidad

### Viabilidad Técnica

**Favorable.** El dominio de gestión de inventario es un problema tecnológicamente maduro con patrones de solución bien establecidos. Las tecnologías requeridas (APIs REST, arquitectura cloud, RBAC, observabilidad) son ampliamente disponibles. La adopción de DDD, BDD y ATDD reduce la deuda técnica desde el inicio.

### Viabilidad Operacional

**Favorable.** Los stakeholders clave están identificados y comprometidos. Los usuarios operativos gestionan actualmente los procesos que el sistema reemplazará, lo que facilita la transferencia de conocimiento. Se requiere gestión de cambio activa para reducir la resistencia de usuarios finales.

### Viabilidad Económica

**Favorable.** La eliminación de reprocesos manuales, la reducción de errores de inventario y la mejora en planificación de abastecimiento generan retorno medible sobre la inversión. El rango de inversión estimado (USD 80.000–150.000) es proporcional al alcance y los beneficios esperados.

### Viabilidad de Cronograma

**Favorable con reservas.** La duración estimada de 6 meses es ajustada pero alcanzable si el alcance se mantiene controlado. Las integraciones con proveedores externos representan el principal riesgo de cronograma y deben iniciarse temprano.

---

## 10. Evaluación Inicial de Riesgos

| Riesgo                                              | Probabilidad | Impacto | Estrategia de Mitigación                                                      |
|-----------------------------------------------------|:------------:|:-------:|-------------------------------------------------------------------------------|
| Cambios frecuentes en requerimientos de negocio     | Alta         | Alto    | Definir proceso de control de cambios; ciclos cortos de validación con usuarios |
| Retrasos en integraciones con proveedores externos  | Alta         | Alto    | Iniciar negociación en fase de análisis; definir contratos de integración tempranos |
| Calidad insuficiente de datos iniciales de inventario | Media      | Alto    | Plan de migración y limpieza de datos previo a go-live                        |
| Resistencia al cambio por usuarios operativos       | Media        | Medio   | Plan de gestión de cambio, capacitación temprana e involucramiento de usuarios clave |
| Dependencia de servicios externos de notificación   | Baja         | Medio   | Diseñar el sistema con soporte para múltiples proveedores de notificación      |
| Incremento no planificado del volumen de transacciones | Baja      | Alto    | Arquitectura escalable desde el diseño; pruebas de carga antes del go-live    |
| Desviación del presupuesto estimado                 | Media        | Alto    | Monitoreo de costos mensual; gestión estricta del alcance                     |

---

## 11. Cronograma de Alto Nivel

| Fase                          | Duración Estimada | Descripción                                              |
|-------------------------------|:-----------------:|----------------------------------------------------------|
| Análisis de Requerimientos    | 4 semanas         | Levantamiento detallado, validación con stakeholders     |
| Diseño de Arquitectura y UX   | 3 semanas         | Arquitectura técnica, diseño de interfaces y modelo de datos |
| Desarrollo — Iteración 1      | 5 semanas         | Core de inventario: productos, stock, movimientos        |
| Desarrollo — Iteración 2      | 5 semanas         | Alertas, reportería, dashboard, gestión de proveedores   |
| Desarrollo — Iteración 3      | 4 semanas         | Integraciones externas, APIs, auditoría                  |
| Pruebas y QA                  | 3 semanas         | Pruebas funcionales, de carga, seguridad y aceptación    |
| Despliegue y Go-Live          | 2 semanas         | Migración de datos, capacitación, puesta en producción   |
| **Total**                     | **~26 semanas**   | **Aprox. 6 meses**                                       |

---

## 12. Estimación Inicial de Costos

| Categoría                              | Costo Estimado (USD)  |
|----------------------------------------|-----------------------|
| Desarrollo de software                 | 50.000 – 90.000       |
| Infraestructura cloud                  | 8.000 – 15.000        |
| Bases de datos                         | 3.000 – 6.000         |
| Licencias de herramientas y servicios  | 2.000 – 5.000         |
| Monitoreo y observabilidad             | 2.000 – 5.000         |
| Seguridad y auditoría                  | 3.000 – 8.000         |
| Pruebas y aseguramiento de calidad     | 5.000 – 10.000        |
| Capacitación y transferencia de conocimiento | 3.000 – 7.000   |
| Gestión de proyecto y contingencia     | 4.000 – 4.000         |
| **Total estimado**                     | **80.000 – 150.000**  |

> Los costos de desarrollo varían según el modelo de contratación (equipo interno, staff augmentation o outsourcing). Se recomienda refinar esta estimación al cierre de la fase de Análisis de Requerimientos.

---

## 13. Criterios de Éxito

| Criterio                                          | Indicador Medible                                              |
|---------------------------------------------------|----------------------------------------------------------------|
| Reducción de errores de inventario                | Disminución ≥ 80% de inconsistencias vs. proceso manual       |
| Eficiencia en generación de reportes              | Reducción ≥ 70% del tiempo de elaboración de reportes gerenciales |
| Disponibilidad del sistema                        | Uptime ≥ 99,9% medido mensualmente en producción              |
| Adopción de usuarios                              | ≥ 90% de usuarios operativos activos en los primeros 30 días  |
| Tiempo de respuesta                               | Consultas de inventario respondidas en < 2 segundos (P95)     |
| Integraciones operativas                          | 100% de integraciones definidas en alcance funcionando en go-live |
| Trazabilidad de operaciones                       | 100% de movimientos de inventario auditables en el sistema    |
| Satisfacción de usuarios clave                    | Calificación ≥ 4/5 en encuesta post-implementación            |

---

## 14. Recomendación y Próximos Pasos

### Recomendación

El proyecto ControlStock presenta justificación de negocio sólida, viabilidad técnica y económica favorable, y stakeholders comprometidos. **Se recomienda aprobar el proyecto e iniciar formalmente la siguiente etapa del SDLC.**

### Siguiente Etapa SDLC: Análisis de Requerimientos

La etapa siguiente es el **Análisis de Requerimientos**, cuyo objetivo es transformar los requerimientos de alto nivel definidos en este PID en especificaciones detalladas que sirvan como base para el diseño y desarrollo del sistema.

### Actividades Recomendadas para la Siguiente Fase

- Designar formalmente al Project Manager del proyecto.
- Convocar kickoff con todos los stakeholders para alinear expectativas y metodología de trabajo.
- Realizar sesiones de levantamiento de requerimientos con usuarios clave (Supervisor de Inventario, Área de Compras, Área de TI).
- Documentar casos de uso y flujos de negocio prioritarios.
- Definir criterios de aceptación para cada requerimiento funcional (BDD/ATDD).
- Mapear e iniciar conversaciones de integración con proveedores externos.
- Elaborar el Plan de Gestión de Cambio para usuarios operativos.
- Refinar la estimación de costos con base en requerimientos detallados.
- Validar y aprobar el documento de Especificación de Requerimientos con stakeholders.

---

*Documento generado como parte de la etapa de Planeación del SDLC — ControlStock.*
