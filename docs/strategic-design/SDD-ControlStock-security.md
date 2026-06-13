# Strategic Design Document — Seguridad

**Proyecto:** ControlStock | Parte del conjunto SDD — etapa Strategic Design / Pre-Design del SDLC.
Documentos complementarios: `SDD-ControlStock-domain.md` · `SDD-ControlStock-architecture.md`

---

## 1. Modelo de Seguridad

### Principios de Seguridad

- **Zero Trust:** ningún actor interno o externo es confiable por defecto; toda petición se autentica y autoriza explícitamente.
- **Least Privilege:** cada actor (usuario, servicio, proceso) recibe únicamente los permisos mínimos necesarios para cumplir su función.
- **Defense in Depth:** múltiples capas de control (Kong, RBAC, red K3s, Vault, TLS, auditoría) de modo que la vulneración de una capa no comprometa el sistema completo.
- **Secure by Default:** toda nueva ruta, endpoint o servicio está denegado por defecto hasta que se otorguen permisos explícitos.
- **Fail Securely:** ante error, el sistema deniega el acceso; nunca falla abierto.
- **Separation of Concerns:** los servicios de identidad (Keycloak), secretos (Vault), gateway (Kong) y dominio de negocio son componentes independientes con responsabilidades no solapadas.

---

### Identidad y Autenticación

Modelo conceptual basado en OIDC/OAuth 2.0:

- **Proveedor de identidad:** Keycloak, realm `controlstock`, desplegado en namespace `identity` de K3s.
- **Mecanismo de autenticación de usuarios:** credenciales (usuario/email + contraseña hasheada con bcrypt) gestionadas por Keycloak. Las contraseñas nunca se almacenan en texto plano en ningún componente del sistema.
- **Tokens de sesión:** JWT firmados con RS256 (clave privada en Keycloak). Cada token incluye los claims de roles y permisos del usuario. Los tokens tienen tiempo de expiración configurable y soporte para revocación inmediata.
- **Autenticación de API externa (RF-020):** tokens de API independientes de los tokens de sesión de usuario. Gestionados por Kong; los permisos asociados se administran mediante el módulo RBAC.
- **Validación de tokens:** Kong API Gateway intercepta y valida el JWT RS256 en cada petición entrante antes de enrutar al servicio backend. Los microservicios internos confían en los claims del JWT ya validado por Kong.

---

### Autorización

Control de acceso basado en roles (RBAC) con permisos granulares por módulo y operación.

| Rol | Bounded Contexts accesibles | Nivel de Acceso |
|-----|-----------------------------|-----------------|
| Operador de Inventario | Inventory (BC-03) | Registrar entradas y salidas; consultar stock y Kardex |
| Operador de Inventario | Adjustment (BC-04) | Crear solicitudes de ajuste |
| Supervisor de Inventario | Inventory (BC-03) | Consultar stock y Kardex; anular movimientos (con permiso explícito) |
| Supervisor de Inventario | Adjustment (BC-04) | Aprobar y rechazar ajustes |
| Supervisor de Inventario | Alert (BC-05) | Configurar alertas; consultar alertas activas |
| Supervisor de Inventario | Reporting (BC-07) | Generar y descargar reportes operativos |
| Administrador del Sistema | IAM (BC-01) | Gestión total: usuarios, roles, permisos |
| Administrador del Sistema | Catalog (BC-02) | Gestión total: productos, categorías |
| Administrador del Sistema | Supplier (BC-06) | Gestión total: proveedores, configuración de integración |
| Administrador del Sistema | Integration (BC-09) | Configurar integraciones y monitorear sagas |
| Gerente / Analista | Reporting (BC-07) | Generar y descargar todos los tipos de reporte |
| Gerente / Analista | Dashboard (Inventory / Reporting) | Consulta de KPIs (solo lectura) |
| API Consumer Externo | Inventory (BC-03) vía API pública | Consultar stock, registrar movimientos, obtener Kardex (según permisos del token de API) |
| Auditor | Audit (BC-08) | Consulta de registros de auditoría (solo lectura) |

---

### Datos Sensibles

| Dato | Clasificación | Justificación |
|------|--------------|---------------|
| Contraseñas de usuarios | Crítico | Autenticación del sistema; almacenadas en Keycloak como hash bcrypt; nunca en texto plano |
| Credenciales de integración de proveedores (API keys, passwords FTP/SFTP) | Crítico | Acceso a sistemas externos; almacenadas exclusivamente en HashiCorp Vault KV v2 (`controlstock/<env>/integration-service`) |
| Tokens JWT activos | Alto | Identidad del usuario en cada sesión; expiración configurable; revocación inmediata disponible |
| Tokens de API pública (RF-020) | Alto | Acceso a la API pública de ControlStock; gestionados por Kong |
| Datos de contacto de proveedores (información fiscal, datos de contacto) | Medio | Información comercial sensible; almacenada cifrada en BD |
| Datos de auditoría (operaciones con valores antes/después) | Medio | Trazabilidad de operaciones; acceso restringido a rol Auditor / Administrador |
| Registros del Kardex | Bajo | Historial de movimientos de inventario; datos operativos no personales; acceso por rol |
| Configuración de umbrales de stock | Bajo | Parámetros operativos del negocio; acceso por rol Supervisor / Administrador |

---

### Auditoría

Todo evento relevante de negocio y seguridad genera un `AuditRecord` inmutable en `controlstock_audit`:

- Creación, modificación e inactivación de cualquier entidad (usuarios, productos, categorías, proveedores, roles).
- Registro de movimientos de inventario (entradas, salidas, ajustes).
- Ciclo completo de ajustes (solicitud, aprobación/rechazo).
- Intentos de autenticación fallidos (persistidos en Keycloak y opcionalmente en BC-08).
- Accesos denegados a endpoints protegidos (registrados por Kong y/o el servicio afectado).
- Resultados de integraciones externas (éxito y fallo).
- Eventos de compensación de saga (`AjusteRevertido`, `EntradaRevertida`).

**Requisitos de retención:** el `audit_log` es inmutable e indefinido (RN-011). Los movimientos de Kardex se retienen por el período fiscal aplicable (mínimo 5 años, a confirmar con área legal/contable).

**Acceso a auditoría:** restringido a usuarios con permiso explícito sobre el módulo de auditoría. El log no es modificable ni eliminable por ningún usuario ni proceso.

---

## 2. Threat Modeling

Amenazas identificadas usando el marco STRIDE, ordenadas por impacto descendente.

| ID | Categoría STRIDE | Amenaza | Componente Afectado | Impacto | Mitigación Propuesta |
|----|-----------------|---------|---------------------|---------|----------------------|
| TH-001 | Spoofing | Suplantación de identidad de usuario mediante credenciales robadas o tokens falsificados | IAM (BC-01), Kong | Alto | JWT RS256 firmado con clave de Keycloak; token de corta duración con revocación inmediata; Kong valida firma en cada petición |
| TH-002 | Elevation of Privilege | Escalada de privilegios mediante manipulación de claims JWT o asignación indebida de roles | Kong, IAM (BC-01) | Alto | Claims JWT inmutables en token firmado; Kong valida firma RS256 antes de aceptar claims; RBAC aplicado en el servicio receptor |
| TH-003 | Tampering | Alteración de registros de Kardex o Auditoría para ocultar operaciones | Inventory (BC-03), Audit (BC-08) | Alto | Tabla `audit_log` y `inventory_movements` append-only; sin operaciones DELETE/UPDATE sobre registros existentes; Outbox pattern garantiza consistencia con el evento publicado |
| TH-004 | Repudiation | Negación de movimientos de inventario o aprobaciones de ajustes ejecutadas | Inventory (BC-03), Adjustment (BC-04), Audit (BC-08) | Alto | Audit log inmutable con usuario autenticado, timestamp UTC y valores antes/después; el JWT del usuario queda en el payload del evento de dominio |
| TH-005 | Information Disclosure | Exposición de credenciales de integración (API keys de proveedores, passwords FTP) en código, logs o BD | Integration (BC-09), Supplier (BC-06) | Alto | Credenciales almacenadas exclusivamente en Vault KV v2 (`controlstock/<env>/integration-service`); referenciadas en runtime por `spring-cloud-vault-config`; nunca commiteadas en repositorio (gitleaks en pipeline) |
| TH-006 | Information Disclosure | Exposición de datos de stock e inventario a sistemas externos no autorizados vía API pública (RF-020) | Kong, Integration (BC-09) | Alto | Tokens de API independientes validados por Kong; RBAC en cada endpoint; rate limiting 200 req/min; respuestas de error sin datos internos |
| TH-007 | Spoofing | Suplantación de proveedor externo en respuesta a una solicitud de reposición | Integration (BC-09) | Alto | HTTPS/TLS en todas las llamadas salientes; API key del proveedor almacenada en Vault; validación de estructura de respuesta en ACL; WireMock en pruebas de integración |
| TH-008 | Denial of Service | Saturación del API Gateway o microservicios por volumen de peticiones anómalas | Kong | Medio | Rate limiting global 200 req/min en Kong; K3s HPA para auto-scaling de servicios críticos; Prometheus alertas de latencia y tasa de errores |
| TH-009 | Tampering | Inyección de eventos maliciosos en Kafka para alterar el stock o disparar alertas falsas | Apache Kafka (Strimzi) | Medio | TLS en broker Kafka (Strimzi); ACLs de productor/consumidor por servicio; solo `inventory-service` es productor autorizado de `StockActualizado` |
| TH-010 | Information Disclosure | Fuga de secretos o datos sensibles en logs estructurados accesibles por Grafana Loki | Todos los microservicios | Medio | Logback/MDC configurado para excluir campos sensibles (passwords, tokens, API keys); acceso a Grafana Loki restringido por autenticación; alertas ante patrones de secret en logs (gitleaks en pipeline) |
| TH-011 | Tampering | Alteración de imágenes Docker en el registry o del artefacto en el pipeline CI/CD | Gitea Registry, Jenkins | Medio | Trivy image scan ante CVE crítico falla el pipeline; OWASP Dependency Check; digest de imagen verificado por ArgoCD; gitleaks en cada commit |
| TH-012 | Repudiation | Negación de configuración de cambio de roles o permisos RBAC | IAM (BC-01) | Medio | Audit log de toda operación sobre usuarios y roles; solo Administrador puede modificar roles; operación registrada con JWT del Administrador |
| TH-013 | Denial of Service | Fallo del servicio externo de notificaciones que bloquee el procesamiento de alertas | Alert (BC-05), Integration (BC-09) | Bajo | Diseño desacoplado: las alertas se registran en BD independientemente del éxito del envío externo; reintentos con backoff exponencial; Circuit Breaker en `integration-service` |

---

## 3. Trust Boundaries

### Zonas de Confianza

| Zona | Descripción | Nivel de Confianza |
|------|-------------|-------------------|
| Zona Externa (Internet) | Usuarios finales mediante navegador, sistemas externos API consumers, proveedores externos, servicios de notificación | Externo (sin confianza implícita) |
| Zona DMZ / Gateway | Kong API Gateway (puerto 8000 VPS), Traefik Ingress (frontend Next.js) | Bajo (punto de entrada controlado) |
| Zona de Aplicación (K3s namespace `apps`) | Todos los microservicios backend de ControlStock | Alto (tráfico interno K3s) |
| Zona de Identidad (K3s namespace `identity`) | Keycloak — proveedor de identidad OIDC | Alto (sistema crítico) |
| Zona de Datos (K3s namespace `data`) | PostgreSQL 16, MongoDB 7 | Alto (solo accesible desde Zona de Aplicación) |
| Zona de Mensajería (K3s namespace `infra`) | Apache Kafka (Strimzi), Narayana LRA | Alto (solo accesible desde Zona de Aplicación) |
| Zona de Secretos (K3s namespace `secrets`) | HashiCorp Vault KV v2 | Muy Alto (solo acceso autenticado con AppRole) |
| Zona de Observabilidad (K3s namespace `monitoring`) | Prometheus, Grafana, Loki, Grafana Tempo | Alto (acceso restringido por autenticación Grafana) |
| Zona CI/CD (K3s namespace `cicd`) | Jenkins, ArgoCD, Gitea | Alto (acceso restringido; pipeline automatizado) |

---

### Flujos que Cruzan Trust Boundaries

| Origen | Destino | Dato / Acción | Riesgo | Control Requerido |
|--------|---------|--------------|--------|------------------|
| Usuario (Externo) | Kong (DMZ) | Credenciales o JWT en header Authorization | Intercepción, suplantación | HTTPS/TLS obligatorio; Kong valida JWT RS256; rate limiting |
| Sistema Externo API Consumer (Externo) | Kong (DMZ) | Token de API + payload REST | Acceso no autorizado, abuso de API | Token de API validado por Kong; RBAC por endpoint; rate limiting 200 req/min |
| Kong (DMZ) | Microservicios (Aplicación) | JWT claims + payload de petición | Forwarding de token no validado | Kong siempre valida antes de enrutar; servicios internos confían en claims pre-validados; no exposición directa de pods |
| Microservicios (Aplicación) | PostgreSQL / MongoDB (Datos) | Datos de inventario, usuarios, auditoría | SQL injection, acceso no autorizado | Credenciales desde Vault en runtime; queries parametrizadas (R2DBC / MongoTemplate); network policy K3s restringe acceso |
| Microservicios (Aplicación) | Kafka (Mensajería) | Eventos de dominio | Inyección de eventos maliciosos | TLS en broker (Strimzi); ACLs por servicio productor/consumidor |
| Microservicios (Aplicación) | Vault (Secretos) | Lectura de secretos en runtime | Robo de credenciales | AppRole authentication; TTL corto en leases de secretos; audit log de Vault activo |
| `integration-service` (Aplicación) | Proveedor Externo (Externo) | Solicitudes REST / archivos FTP | MITM, suplantación de proveedor, data tampering | HTTPS/TLS en llamadas salientes; API key del proveedor en Vault; validación de respuesta en ACL; timeout y Circuit Breaker |
| `integration-service` (Aplicación) | Servicio de Notificaciones (Externo) | Mensajes de alerta (contenido mínimo) | Exposición de datos de inventario, spam | API key en Vault; contenido de notificación limitado al mínimo necesario; TLS; reintentos controlados |
| Jenkins (CI/CD) | Gitea Registry / K3s | Imágenes Docker, manifiestos de despliegue | Supply chain attack, inyección de código | Trivy scan (falla ante CVE crítico); OWASP Dependency Check; gitleaks; digest de imagen verificado; quality gate SonarQube obligatorio |
| Navegador (Externo) | Traefik / Next.js (DMZ / Aplicación) | Sesión de usuario, datos de pantalla | XSS, CSRF, intercepción | HTTPS/TLS en Traefik; Next.js con headers de seguridad (CSP, HSTS); validación de token en cada llamada a Kong |

---

*Generado como parte del Strategic Design del SDLC — ControlStock.*
*Documentos complementarios: `SDD-ControlStock-domain.md` · `SDD-ControlStock-architecture.md`*
