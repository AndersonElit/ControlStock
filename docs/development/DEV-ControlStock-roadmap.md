# Plan de Desarrollo — ControlStock

---

## 1. Introducción

Este documento describe el plan maestro de desarrollo para el sistema **ControlStock**, un sistema web centralizado de gestión de inventario para el sector Retail. La etapa de Implementación toma como entrada los artefactos producidos en las etapas de Análisis de Requerimientos, Diseño Estratégico y Diseño Técnico, y los traduce en código ejecutable, infraestructura aprovisionada y pipelines de entrega continua.

### Objetivo de la etapa

Construir, integrar y desplegar todos los componentes del sistema ControlStock en un ambiente K3s sobre VPS, de forma incremental, siguiendo la secuencia de dependencias definida en el Diseño Técnico. Al finalizar esta etapa, el sistema debe:

- Estar completamente desplegado en el ambiente `local` (QEMU/KVM) con paridad estructural respecto al ambiente `prod` (Oracle Cloud OCI).
- Pasar todos los criterios de aceptación funcionales y no funcionales definidos en el SRS y en los planes de prueba.
- Contar con pipelines CI/CD operativos (Jenkins + ArgoCD) para cada microservicio y para el frontend.
- Exponer observabilidad completa (métricas, logs, trazas) mediante la pila Prometheus + Grafana + Loki + Tempo.

### Ambiente objetivo

| Dimensión | Local | Producción |
|---|---|---|
| Hipervisor / Cloud | QEMU/KVM (`qemu-vps.sh`) | Oracle Cloud OCI |
| Orquestador | K3s (modo single-node) | K3s (modo single-node) |
| IaC | Terraform ≥ 1.7 | Terraform ≥ 1.7 |
| Gestión de charts | Helm 3.x | Helm 3.x |
| Entorno lógico | `local` | `prod` |
| IP de acceso | `<VPS_IP>` (asignada por QEMU) | IP pública OCI |
| WireMock | Habilitado | Deshabilitado (`--no-wiremock`) |

### Tecnologías involucradas

| Capa | Tecnología | Versión |
|---|---|---|
| Lenguaje backend | Java (Spring Boot) | Java 21 / Spring Boot 3.x |
| Lenguaje ETL | Scala (Apache Spark) | Scala 2.13 / Spark 3.5.1 |
| Lenguaje funciones | Python | 3.11+ |
| Frontend | Next.js | 14.x |
| Base de datos relacional | PostgreSQL | 16 |
| Base de datos documental | MongoDB | 7 |
| Mensajería | Apache Kafka (Strimzi KRaft) | 3.x |
| Integración / Saga | Apache Camel + Narayana LRA | Camel 4.10.2 / LRA 7.x |
| API Gateway | Kong | 3.x |
| Identity & Access | Keycloak | 24 |
| Gestión de secretos | HashiCorp Vault KV v2 | — |
| Almacenamiento objetos | MinIO | — |
| Functions | OpenFaaS | — |
| Orquestación CI | Jenkins | — |
| GitOps CD | ArgoCD | — |
| Registro Git | Gitea | — |
| Imagen registry | Gitea Package Registry / OCIR | — |
| IaC | Terraform + Helm | ≥ 1.7 |
| Simulación dependencias | WireMock | — |
| Testing contratos | Pact | — |
| Testing E2E | Playwright + REST Assured | — |
| Testing carga | k6 | — |

---

## 2. Prerrequisitos Globales

Antes de iniciar cualquier etapa de desarrollo, la estación de trabajo del desarrollador (o la máquina de CI) debe tener instaladas las siguientes herramientas. Los comandos de instalación se asumen sobre Ubuntu 24.04 LTS o equivalente.

### Herramientas obligatorias

| Herramienta | Versión mínima | Propósito |
|---|---|---|
| Terraform | ≥ 1.7 | Aprovisionamiento de infraestructura K3s |
| kubectl | ≥ 1.29 | Administración del clúster K3s |
| Helm | ≥ 3.14 | Instalación de charts Kubernetes |
| Java (JDK) | 21 (LTS) | Compilación y ejecución de microservicios Spring Boot |
| Maven | ≥ 3.9 | Build de proyectos Java |
| Node.js | 20 LTS | Build del frontend Next.js |
| npm / pnpm | ≥ 10 | Gestión de dependencias frontend |
| Python | 3.11+ | Funciones OpenFaaS, scripts de utilidad |
| sbt | 1.9+ | Build del proyecto Spark/Scala (report-etl-service) |
| Docker | ≥ 25 | Build de imágenes de contenedores |
| QEMU/KVM | — | VPS local (entorno `local`) |
| faas-cli | — | Deploy de funciones OpenFaaS |
| k6 | — | Pruebas de carga y estrés |
| Playwright CLI | — | Pruebas E2E frontend |

### Verificación de herramientas

```bash
terraform --version    # debe indicar >= 1.7
kubectl version --client
helm version
java --version         # debe indicar java 21
mvn --version
node --version         # debe indicar v20.x
python3 --version      # debe indicar 3.11+
sbt --version          # debe indicar 1.9+
docker --version
faas-cli version
k6 version
```

### Provisión del VPS local (QEMU/KVM)

El script `qemu-vps.sh` crea y configura una VM Ubuntu sobre KVM con los recursos necesarios para ejecutar K3s:

```bash
bash .claude/scripts/qemu-vps.sh \
  --name controlstock-local \
  --memory 8192 \
  --cpus 4 \
  --disk 60G \
  --os ubuntu-24.04
```

Tras la ejecución, el script imprime la IP asignada (`<VPS_IP>`). Esta IP debe exportarse como variable de entorno antes de ejecutar cualquier paso posterior:

```bash
export VPS_IP=<VPS_IP>
```

### Provisión del VPS en producción (Oracle Cloud OCI)

Para el ambiente `prod`, el VPS se aprovisiona en Oracle Cloud OCI mediante los módulos Terraform de la organización. El proceso requiere credenciales OCI configuradas (`~/.oci/config`) y la ejecución del módulo `oci-compute`:

```bash
terraform -chdir=infra/oci init
terraform -chdir=infra/oci apply -var="project=controlstock" -var="env=prod"
```

La IP pública resultante debe sustituir a `<VPS_IP>` en todas las configuraciones del ambiente `prod`.

---

## 3. Secuencia de Etapas

La siguiente tabla lista todas las etapas del plan de desarrollo, con sus documentos de referencia, dependencias y estimación en días de trabajo de un desarrollador senior.

| Etapa | Documento | Descripción | Dependencias | Estimación |
|---|---|---|---|---|
| Etapa 0 | [DEV-ControlStock-00-infrastructure.md](DEV-ControlStock-00-infrastructure.md) | Infraestructura VPS: K3s, PostgreSQL, MongoDB, Kafka, Keycloak, Vault, Gitea, Jenkins, ArgoCD, Kong, MinIO, Narayana LRA, WireMock | VPS provisionado (QEMU / OCI) | 1 día |
| Etapa 0c | [DEV-ControlStock-00c-observability.md](DEV-ControlStock-00c-observability.md) | Configuración de observabilidad: Prometheus, Grafana, Loki, Promtail, Tempo — dashboards base y alertas de infraestructura | Etapa 0 | 0.5 días |
| Etapa 1 | [DEV-ControlStock-01-databases.md](DEV-ControlStock-01-databases.md) | Bases de datos: creación de 9 esquemas PostgreSQL (`controlstock_*`), índices, roles, colecciones MongoDB, topics Kafka | Etapa 0 | 1 día |
| Etapa 2 | [DEV-ControlStock-02-scaffold.md](DEV-ControlStock-02-scaffold.md) | Scaffolding: estructura de repositorios Git, archivos base Maven/pom.xml, librerías compartidas (commons), convenciones de código, configuración de Vault | Etapa 0, Etapa 1 | 1 día |
| Etapa 2b | [DEV-ControlStock-02b-cicd.md](DEV-ControlStock-02b-cicd.md) | CI/CD: pipelines Jenkins (build, test, push imagen), apps ArgoCD, Helm charts por servicio, GitOps manifests | Etapa 2 + Gitea/Jenkins/ArgoCD en Etapa 0 | 1 día |
| Etapa 3a | [DEV-ControlStock-03a-iam-service.md](DEV-ControlStock-03a-iam-service.md) | BC-01 iam-service: usuarios, roles, permisos, integración Keycloak | Etapa 2b | 2 días |
| Etapa 3b | [DEV-ControlStock-03b-catalog-service.md](DEV-ControlStock-03b-catalog-service.md) | BC-02 catalog-service: gestión de productos y categorías, outbox, proyección MongoDB | Etapa 3a | 2 días |
| Etapa 3c | [DEV-ControlStock-03c-supplier-service.md](DEV-ControlStock-03c-supplier-service.md) | BC-06 supplier-service: gestión de proveedores, outbox, proyección MongoDB | Etapa 3a | 2 días |
| Etapa 3d | [DEV-ControlStock-03d-adjustment-service.md](DEV-ControlStock-03d-adjustment-service.md) | BC-04 adjustment-service: solicitudes de ajuste, compensación Saga-02 | Etapa 3a | 2 días |
| Etapa 3e | [DEV-ControlStock-03e-inventory-service.md](DEV-ControlStock-03e-inventory-service.md) | BC-03 inventory-service: stock, movimientos, Kardex, proyección MongoDB, compensación Saga-01 y Saga-02 | Etapa 3b, 3c, 3d | 3 días |
| Etapa 3f | [DEV-ControlStock-03f-alert-service.md](DEV-ControlStock-03f-alert-service.md) | BC-05 alert-service: reglas de alerta, consumo Kafka `stock-actualizado`, REST call a integration-service | Etapa 3e | 1.5 días |
| Etapa 3g | [DEV-ControlStock-03g-report-service.md](DEV-ControlStock-03g-report-service.md) | BC-07 report-service: catálogo de reportes, solicitudes, archivos, consumo Kafka `parquet-generado` | Etapa 3e | 1.5 días |
| Etapa 3h | [DEV-ControlStock-03h-audit-service.md](DEV-ControlStock-03h-audit-service.md) | BC-08 audit-service: consumidor Kafka ALL events, registro de auditoría append-only | Etapa 3e | 1 día |
| Etapa 3i | [DEV-ControlStock-03i-integration-service.md](DEV-ControlStock-03i-integration-service.md) | BC-09 integration-service: ACL, orquestación Saga-01 y Saga-02 (Camel + LRA), notificaciones | Etapas 3d, 3e, 3f (endpoint compensación disponible) | 3 días |
| Etapa 3j | [DEV-ControlStock-03j-report-etl-service.md](DEV-ControlStock-03j-report-etl-service.md) | report-etl-service: Spark/Scala CronJob — lee MongoDB `controlstock_readmodel` y `controlstock_audit`, escribe .parquet en MinIO | Etapas 3e, 3h (read model poblado) | 2 días |
| Etapa 3k | [DEV-ControlStock-03k-report-format-consumer.md](DEV-ControlStock-03k-report-format-consumer.md) | report-format-consumer: OpenFaaS python3-http — lee parquet de MinIO, genera XLSX/CSV/PDF, notifica report-service | Etapa 3j | 1 día |
| Etapa 4a | [DEV-ControlStock-04a-frontend-auth.md](DEV-ControlStock-04a-frontend-auth.md) | Frontend — Feature auth: login, callback OIDC Keycloak | Etapa 3a | 1 día |
| Etapa 4b | [DEV-ControlStock-04b-frontend-dashboard.md](DEV-ControlStock-04b-frontend-dashboard.md) | Frontend — Feature dashboard: stock overview, alertas resumen | Etapas 3e, 3f, 4a | 1 día |
| Etapa 4c | [DEV-ControlStock-04c-frontend-catalogo.md](DEV-ControlStock-04c-frontend-catalogo.md) | Frontend — Feature catálogo: productos y categorías | Etapas 3b, 4a | 1 día |
| Etapa 4d | [DEV-ControlStock-04d-frontend-inventario.md](DEV-ControlStock-04d-frontend-inventario.md) | Frontend — Feature inventario: stock, movimientos, Kardex | Etapas 3e, 4a | 1.5 días |
| Etapa 4e | [DEV-ControlStock-04e-frontend-ajustes.md](DEV-ControlStock-04e-frontend-ajustes.md) | Frontend — Feature ajustes: solicitudes, aprobación/rechazo | Etapas 3d, 3i, 4a | 1.5 días |
| Etapa 4f | [DEV-ControlStock-04f-frontend-alertas.md](DEV-ControlStock-04f-frontend-alertas.md) | Frontend — Feature alertas: consulta y reconocimiento | Etapas 3f, 4a | 1 día |
| Etapa 4g | [DEV-ControlStock-04g-frontend-proveedores.md](DEV-ControlStock-04g-frontend-proveedores.md) | Frontend — Feature proveedores: gestión de proveedores | Etapas 3c, 4a | 1 día |
| Etapa 4h | [DEV-ControlStock-04h-frontend-reportes.md](DEV-ControlStock-04h-frontend-reportes.md) | Frontend — Feature reportes: generación y descarga | Etapas 3g, 3k, 4a | 1.5 días |
| Etapa 4i | [DEV-ControlStock-04i-frontend-auditoria.md](DEV-ControlStock-04i-frontend-auditoria.md) | Frontend — Feature auditoría: log de auditoría | Etapas 3h, 4a | 1 día |
| Etapa 4j | [DEV-ControlStock-04j-frontend-administracion.md](DEV-ControlStock-04j-frontend-administracion.md) | Frontend — Feature administración: usuarios y roles IAM | Etapas 3a, 4a | 1 día |
| Etapa 5 | [DEV-ControlStock-05-integration-tests.md](DEV-ControlStock-05-integration-tests.md) | Pruebas de integración end-to-end: contratos Pact, E2E Playwright + REST Assured, pruebas de carga k6 | Todas las etapas 3x y 4x | 2 días |

**Total estimado:** ~37.5 días de desarrollo de un desarrollador senior (sin contar revisiones, onboarding ni contingencias).

---

## 4. Mapa de Microservicios

| Servicio | Bounded Context | BD propietaria | Motor BD | Mensajería | Dependencias REST salientes | Sistemas externos | Rol en Saga |
|---|---|---|---|---|---|---|---|
| iam-service | BC-01 | `controlstock_iam` | PostgreSQL 16 | — | — | Keycloak 24 | — |
| catalog-service | BC-02 | `controlstock_catalog` | PostgreSQL 16 + MongoDB (read model: `productos`) | Publica: `producto-creado`, `producto-actualizado`, `producto-inactivado` | — | — | — |
| inventory-service | BC-03 | `controlstock_inventory` | PostgreSQL 16 + MongoDB (read model: `kardex`, `movimientos`, `stock`) | Publica: `entradas`, `salidas`, `stock-actualizado` | — | — | Participante Saga-01 (entrada inventario) y Saga-02 (aplicar stock); compensación: `POST /inventory/movements/{id}/compensar` |
| adjustment-service | BC-04 | `controlstock_adjustment` | PostgreSQL 16 | Publica: `ajuste-solicitado`, `ajuste-aprobado`, `ajuste-rechazado` | — | — | Participante Saga-02 (crear y aprobar ajuste); compensación: `POST /adjustments/{id}/compensar` |
| alert-service | BC-05 | `controlstock_alert` | PostgreSQL 16 | Consume: `stock-actualizado` | integration-service (notificaciones) | — | — |
| supplier-service | BC-06 | `controlstock_supplier` | PostgreSQL 16 + MongoDB (read model: `proveedores`) | Publica: `proveedor-actualizado` | — | — | — |
| report-service | BC-07 | `controlstock_reporting` | PostgreSQL 16 | Publica: `controlstock.reporting.requests`; consume: `parquet-generado`, `etl-fallido` | — | MinIO (URLs de descarga) | — |
| audit-service | BC-08 | `controlstock_audit` | PostgreSQL 16 | Consume: TODOS los eventos Kafka | — | — | — |
| integration-service | BC-09 | `controlstock_integration` | PostgreSQL 16 | Publica: `solicitud-reposicion-enviada`; consume: `ajuste-aprobado`, `controlstock.reporting.requests` | adjustment-service, inventory-service (compensación), alert-service | Proveedor externo (HTTP via WireMock en local) | Orquestador Saga-01 y Saga-02 (Camel + Narayana LRA) |
| report-etl-service | — (CronJob) | Lee: `controlstock_readmodel` (MongoDB), `controlstock_audit` (JDBC), `controlstock_reporting` (JDBC) | Spark/Scala | Publica: `parquet-generado`, `etl-fallido` | — | MinIO (escritura .parquet) | — |
| report-format-consumer | — (OpenFaaS) | — | Python 3.11 | Activado por `parquet-generado` via Kafka connector | report-service (notificación resultado) | MinIO (lectura .parquet) | — |

### Proyecciones MongoDB (CQRS Read Model)

Las proyecciones MongoDB no son un servicio separado. Los consumers de proyección están **embebidos** dentro de los siguientes servicios:

| Servicio propietario | Colección MongoDB | Base de datos MongoDB | Topics consumidos |
|---|---|---|---|
| catalog-service | `productos` | `controlstock_readmodel` | `producto-creado`, `producto-actualizado`, `producto-inactivado` |
| inventory-service | `kardex`, `movimientos`, `stock` | `controlstock_readmodel` | `entradas`, `salidas`, `stock-actualizado` |
| supplier-service | `proveedores` | `controlstock_readmodel` | `proveedor-actualizado` |

---

## 5. Mapa de Features Frontend

El frontend Next.js 14 consume los microservicios a través de Kong (API Gateway) autenticado con Keycloak OIDC.

| Feature | Rutas principales | Bounded contexts consumidos | Servicios backend |
|---|---|---|---|
| auth | `/login`, `/auth/callback`, `/logout` | BC-01 (IAM) | iam-service, Keycloak (OIDC) |
| dashboard | `/dashboard` | BC-03 (Inventory), BC-05 (Alert) | inventory-service (stock overview), alert-service (alertas activas) |
| catalogo | `/catalogo`, `/catalogo/productos`, `/catalogo/productos/[id]`, `/catalogo/categorias` | BC-02 (Catalog) | catalog-service |
| inventario | `/inventario`, `/inventario/stock`, `/inventario/movimientos`, `/inventario/kardex` | BC-03 (Inventory) | inventory-service |
| ajustes | `/ajustes`, `/ajustes/solicitudes`, `/ajustes/solicitudes/[id]`, `/ajustes/solicitudes/nueva` | BC-04 (Adjustment), BC-09 (Integration) | adjustment-service, integration-service |
| alertas | `/alertas`, `/alertas/[id]` | BC-05 (Alert) | alert-service |
| proveedores | `/proveedores`, `/proveedores/[id]`, `/proveedores/nueva` | BC-06 (Supplier) | supplier-service |
| reportes | `/reportes`, `/reportes/solicitar`, `/reportes/[id]` | BC-07 (Reporting) | report-service |
| auditoria | `/auditoria`, `/auditoria/[id]` | BC-08 (Audit) | audit-service |
| administracion | `/admin`, `/admin/usuarios`, `/admin/usuarios/[id]`, `/admin/roles` | BC-01 (IAM) | iam-service |

### Protección de rutas por rol

| Feature | Roles con acceso |
|---|---|
| auth | Público (sin autenticación requerida) |
| dashboard | Operador, Supervisor, Admin, Gerente, Auditor (todos los roles) |
| catalogo | Operador, Supervisor, Admin, Gerente, Auditor |
| inventario | Operador, Supervisor, Admin, Gerente, Auditor |
| ajustes | Operador (crear), Supervisor (aprobar/rechazar), Admin |
| alertas | Operador, Supervisor, Admin, Gerente, Auditor |
| proveedores | Admin, Gerente |
| reportes | Gerente, Auditor |
| auditoria | Auditor, Admin |
| administracion | Admin |

---

## 6. Ambiente K3s en VPS (Terraform + Helm)

### Descripción del script base-infrastructure-builder.sh

El script `base-infrastructure-builder.sh` es el punto de entrada único para aprovisionar todo el ambiente de infraestructura de ControlStock sobre el VPS. Ejecuta 4 fases en orden:

**Fase 1 — Instalación de K3s:** Instala K3s en el VPS vía SSH, configura el kubeconfig local en `~/.kube/config-controlstock-local` y verifica conectividad con el API server.

**Fase 2 — Inicialización Terraform:** Genera los módulos Terraform bajo `infra/terraform/`, ejecuta `terraform init` y `terraform plan` para validar el árbol de módulos.

**Fase 3 — Aplicación Terraform + Helm:** Ejecuta `terraform apply` que despliega todos los módulos de Helm en el clúster K3s. Los charts se instalan en el orden correcto respetando dependencias de namespace y de inicialización de servicios.

**Fase 4 — Post-instalación:** Inicializa Vault (unseal + almacenamiento de root token en `vault-init.json`), crea el realm `controlstock` en Keycloak, configura los topics Kafka, los buckets MinIO y los repositorios Gitea para el proyecto.

### Módulos Terraform generados

| Módulo | Recursos Helm / Kubernetes | Namespace | NodePort / Acceso |
|---|---|---|---|
| `modules/namespaces` | `kubernetes_namespace` para cada namespace del proyecto | — | — |
| `modules/helm-infra` | Traefik (ingress), cert-manager, Kong 3.x (API Gateway) | `infra` | 80, 443, 8000 (Kong Proxy) |
| `modules/helm-data` | PostgreSQL 16 (Bitnami), MongoDB 7 (Bitnami), Strimzi Operator + KafkaNodePool (KRaft) | `data`, `messaging` | Interno (DNS svc) |
| `modules/helm-identity` | Keycloak 24 (Bitnami) | `identity` | NodePort 8082 |
| `modules/helm-secrets` | HashiCorp Vault (HashiCorp chart) | `secrets` | NodePort 8200 |
| `modules/helm-cicd` | Gitea, Jenkins, ArgoCD | `cicd` | 3000, 8080, 8081 |
| `modules/helm-observability` | kube-prometheus-stack, Loki, Promtail, Tempo | `observability` | 9090 (Prometheus), 3001 (Grafana) |
| `modules/helm-support` | Narayana LRA 7.x, WireMock, OpenFaaS Operator + kafka-connector | `infra`, `openfaas` | 50000 (LRA), 9999 (WireMock) |

### Endpoints del ambiente VPS

| Servicio | Endpoint interno (K8s DNS) | Endpoint externo (NodePort / VPS) | Notas |
|---|---|---|---|
| PostgreSQL | `postgresql.data.svc.cluster.local:5432` | Acceso via `kubectl port-forward` | No expuesto en NodePort |
| MongoDB | `mongo.data.svc.cluster.local:27017` | Acceso via `kubectl port-forward` | No expuesto en NodePort |
| Kafka Bootstrap | `kafka-kafka-bootstrap.messaging.svc.cluster.local:9092` | Acceso via `kubectl port-forward` | No expuesto en NodePort |
| Keycloak | `keycloak.identity.svc.cluster.local:8080` | `http://<VPS_IP>:8082` | Realm: `controlstock` |
| HashiCorp Vault | `vault.secrets.svc.cluster.local:8200` | `http://<VPS_IP>:8200` | KV v2, root token en `vault-init.json` |
| Gitea | `gitea.cicd.svc.cluster.local:3000` | `http://<VPS_IP>:3000/controlstock` | Registry: `<VPS_IP>:3000/controlstock` |
| Jenkins | `jenkins.cicd.svc.cluster.local:8080` | `http://<VPS_IP>:8080` | Pipelines por microservicio |
| ArgoCD | `argocd-server.cicd.svc.cluster.local:80` | `http://<VPS_IP>:8081` | GitOps apps |
| Kong Proxy | `kong-proxy.infra.svc.cluster.local:8000` | `http://<VPS_IP>:8000` | Entrada principal API |
| MinIO API | `minio.data.svc.cluster.local:9000` | `http://<VPS_IP>:9000` | Bucket: `controlstock-reports` |
| MinIO Console | `minio.data.svc.cluster.local:9001` | `http://<VPS_IP>:9001` | Consola web MinIO |
| Prometheus | `prometheus-kube-prometheus-prometheus.observability.svc.cluster.local:9090` | `http://<VPS_IP>:9090` | Métricas |
| Grafana | `grafana.observability.svc.cluster.local:80` | `http://<VPS_IP>:3001` | Dashboards |
| Narayana LRA | `narayana-lra.infra.svc.cluster.local:50000` | Interno (no NodePort) | Coordinador Saga LRA |
| WireMock | `wiremock.infra.svc.cluster.local:8080` | `http://<VPS_IP>:9999` | Solo en entorno `local` |

---

## 7. Criterios de Done (Definition of Done)

Los siguientes criterios deben cumplirse **por cada microservicio o feature** antes de considerarlos completados. Los criterios marcados con `[GLOBAL]` aplican al cierre de la etapa de desarrollo completa.

### Código y calidad

- [ ] El código compila sin errores ni warnings suprimidos manualmente.
- [ ] Se implementa TDD (Test-Driven Development): cada clase de servicio y cada endpoint tiene tests unitarios escritos antes o concurrentemente con la implementación.
- [ ] Cobertura de tests unitarios ≥ 80% por servicio (medida con JaCoCo para Java, pytest-cov para Python, ScalaTest para Scala).
- [ ] Todos los tests unitarios pasan en el pipeline CI (fase `test` de Jenkins).
- [ ] No existen dependencias con versiones `SNAPSHOT` en `pom.xml` para builds de release.
- [ ] El código supera el análisis estático de SonarQube (sin issues críticos ni bloqueantes).
- [ ] Las variables de configuración sensibles (contraseñas, tokens, URLs internas) se leen de HashiCorp Vault KV v2 o de variables de entorno inyectadas por Kubernetes Secrets; nunca están hardcodeadas.

### API y contratos

- [ ] Cada microservicio expone un endpoint `GET /actuator/health` que devuelve `200 OK` con estado `UP`.
- [ ] Cada microservicio expone `GET /actuator/metrics` con métricas en formato Prometheus scrape.
- [ ] Los endpoints REST siguen la convención definida en el Diseño Técnico (paths, verbos HTTP, códigos de respuesta).
- [ ] Los contratos de API entre productores y consumidores están cubiertos por tests de contrato Pact (Consumer-Driven Contract Testing).
- [ ] El API Gateway Kong tiene registradas las rutas correspondientes al servicio con autenticación JWT (Keycloak).

### Infraestructura y despliegue

- [ ] Existe un `Dockerfile` multi-stage para el servicio que produce una imagen mínima (JRE slim para Java, python:slim para Python, eclipse-temurin para Scala).
- [ ] La imagen se publica exitosamente al registro Gitea (`<VPS_IP>:3000/controlstock/<servicio>:<version>`).
- [ ] Existe un Helm chart bajo `helm/<servicio>/` con `values.yaml` parametrizado para `local` y `prod`.
- [ ] El pipeline Jenkins ejecuta: `build → test → build-image → push-image → helm-lint` sin errores.
- [ ] Existe un Application manifest de ArgoCD (`argocd/apps/<servicio>.yaml`) que sincroniza el Helm chart desde Gitea.
- [ ] La aplicación ArgoCD reporta estado `Synced` y `Healthy` después del despliegue.
- [ ] El pod arranca y pasa el `readinessProbe` dentro del `initialDelaySeconds` configurado.

### Mensajería y CQRS

- [ ] Los topics Kafka del servicio están creados con el número de particiones y factor de replicación correctos.
- [ ] Los mensajes publicados en Kafka tienen el esquema JSON definido en el Diseño Técnico.
- [ ] El patrón Outbox está implementado correctamente: los mensajes se persisten en la tabla `outbox` dentro de la misma transacción de dominio antes de ser publicados a Kafka.
- [ ] Los consumers Kafka implementan idempotencia mediante la tabla `processed_message` (servicios que la requieren: inventory-service, adjustment-service, integration-service).
- [ ] Las proyecciones MongoDB se actualizan correctamente cuando llegan eventos Kafka (verificado con tests de integración).

### Sagas (integration-service)

- [ ] `[GLOBAL]` Saga-01 (Reposición de inventario) ejecuta el flujo completo: paso 1 (proveedor externo via WireMock) → paso 2 (inventory-service entrada) y el mecanismo de compensación revierte el estado correctamente ante fallo en cualquier paso.
- [ ] `[GLOBAL]` Saga-02 (Ajuste aprobado) ejecuta el flujo completo: paso 1 (crear ajuste) → paso 2 (aprobar ajuste) → paso 3 (inventory-service aplicar stock) y la compensación revierte los pasos afectados.
- [ ] Los endpoints de compensación de inventory-service (`POST /inventory/movements/{id}/compensar`) y adjustment-service (`POST /adjustments/{id}/compensar`) responden correctamente con `200 OK` y revierten el estado de forma idempotente.
- [ ] El Coordinador LRA (Narayana) registra correctamente las instancias de saga y su estado en `saga_instance` y `saga_step_log`.

### Observabilidad

- [ ] `[GLOBAL]` Todos los microservicios están siendo raspados (scraped) por Prometheus (verificado en `http://<VPS_IP>:9090/targets`).
- [ ] `[GLOBAL]` Los logs estructurados (JSON) de todos los servicios son ingrestos por Loki a través de Promtail.
- [ ] `[GLOBAL]` Las trazas distribuidas (OpenTelemetry / Micrometer Tracing) son enviadas a Tempo y visibles en Grafana.
- [ ] `[GLOBAL]` Existe al menos un dashboard Grafana por cada microservicio con las métricas RED (Rate, Errors, Duration).

### Frontend

- [ ] La feature compila con `next build` sin errores de TypeScript.
- [ ] Las rutas protegidas redirigen a `/login` cuando el usuario no está autenticado.
- [ ] Las rutas con restricción de rol muestran página `403 Forbidden` o redirigen cuando el rol del usuario no tiene acceso.
- [ ] Los componentes de UI tienen tests de componente con Playwright (Component Testing) o con React Testing Library.
- [ ] Las llamadas a la API backend pasan por Kong con el token JWT de Keycloak en el header `Authorization: Bearer <token>`.
- [ ] La feature es funcional en los navegadores Chrome y Firefox (últimas versiones estables).

### Pruebas de integración y aceptación [GLOBAL]

- [ ] Los tests E2E (Playwright para UI + REST Assured para API) cubren los happy paths de todos los flujos definidos en el SRS.
- [ ] Los tests de rendimiento con k6 demuestran que bajo carga de 50 usuarios concurrentes el percentil P95 de latencia es < 500 ms para operaciones de lectura y < 1000 ms para escritura.
- [ ] Los tests de estrés con k6 identifican el punto de saturación del sistema y el sistema se recupera sin intervención manual al reducir la carga.
- [ ] El ambiente `local` es funcionalmente equivalente al ambiente `prod` (misma versión de charts, misma configuración de Vault, mismos topics Kafka).

### Seguridad

- [ ] `[GLOBAL]` Todos los endpoints API (excepto `/actuator/health`) requieren token JWT válido emitido por Keycloak realm `controlstock`.
- [ ] `[GLOBAL]` Los secretos de base de datos, Kafka y Vault se gestionan exclusivamente mediante Kubernetes Secrets inyectados desde Vault Agent Injector o External Secrets Operator.
- [ ] `[GLOBAL]` Las imágenes de contenedor superan el escaneo de vulnerabilidades de Trivy sin issues críticos sin parchear.
- [ ] `[GLOBAL]` Las comunicaciones entre servicios internos al clúster utilizan mTLS cuando el servicio expone datos sensibles.

---

*Generado: 2026-06-13 | Proyecto: ControlStock | Etapa SDLC: Implementación*
