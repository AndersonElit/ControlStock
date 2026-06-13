# Etapa 0c — Stack de Observabilidad

---

## 1. Objetivo y Stack de Observabilidad

### Propósito

Esta etapa documenta la **verificación del stack de observabilidad** desplegado automáticamente por `base-infrastructure-builder.sh` durante la Etapa 0, y detalla la **instrumentación automática** que el scaffold aplica a cada microservicio del proyecto ControlStock.

El objetivo operacional es garantizar visibilidad completa sobre el comportamiento del sistema en tiempo real: métricas de aplicación y JVM, trazas distribuidas end-to-end y logs estructurados con correlación de traceId.

No se requiere modificar código de dominio para habilitar observabilidad. Toda la instrumentación es automática y se inyecta en la capa de infraestructura mediante:

- **OpenTelemetry Java Agent** (agente externo, sin cambios en código de dominio)
- **Micrometer** para métricas de aplicación Spring Boot
- **LogstashEncoder** para logs estructurados en JSON con correlación de trazas

### Stack de Observabilidad por Entorno

| Componente | Local (K3s) | Producción (K3s VPS) | Notas |
|---|---|---|---|
| Recolector de métricas | Prometheus (kube-prometheus-stack) | Prometheus (kube-prometheus-stack) | Scraping automático por anotaciones Pod |
| Visualización y dashboards | Grafana 10.x | Grafana 10.x | Mismo chart, mismas credenciales base |
| Trazas distribuidas (backend) | Grafana Tempo | Grafana Tempo | gRPC OTLP en puerto 4317 |
| Logs estructurados | Grafana Loki + Promtail | Grafana Loki + Promtail | JSON con traceId/spanId |
| Alertas | AlertManager | AlertManager | Rules definidas en Helm values |
| Instrumentación app | OpenTelemetry Java Agent | OpenTelemetry Java Agent | Init container en cada Pod |
| Métricas JVM/app | Micrometer + Prometheus Registry | Micrometer + Prometheus Registry | Endpoint `/actuator/prometheus` |
| Logs app (formato) | LogstashEncoder JSON | LogstashEncoder JSON | Correlacionados con OTEL traceId |

Ambos entornos utilizan **K3s + Helm** como plataforma de despliegue. El módulo `modules/helm-observability` es idéntico en ambos entornos; la única diferencia son los valores de `grafana_admin_password` y el origen de los recursos.

---

## 2. Prerrequisitos

Antes de proceder con la verificación de esta etapa se deben cumplir los siguientes requisitos:

- **Etapa 0 completada** con exit code 0 (`base-infrastructure-builder.sh` finalizado sin errores)
- **K3s operativo** en el entorno objetivo (local o producción)
- **kubectl apuntando** a `~/.kube/config-controlstock-local` para el entorno local
- **Terraform apply de Etapa 0 completado**: el módulo `modules/helm-observability` se instaló automáticamente como parte de la aplicación del plan Terraform

Verificación rápida del estado del clúster:

```bash
# Verificar kubectl apunta al contexto correcto
kubectl config current-context

# Listar nodos del clúster
kubectl get nodes

# Verificar namespace observability existe
kubectl get namespace observability

# Verificar todos los pods del stack de observabilidad
kubectl get pods -n observability
```

Todos los pods deben encontrarse en estado `Running` o `Completed` antes de continuar con las etapas de scaffolding.

---

## 3. Stack de Observabilidad (Instalado en Etapa 0)

### Instalación Automática

**No se requiere ningún script adicional en esta etapa.** El módulo `modules/helm-observability` fue instalado automáticamente durante `terraform apply` de la Etapa 0, como parte de la ejecución de `base-infrastructure-builder.sh`.

El orden de instalación en el plan Terraform fue:

1. Namespace `observability`
2. `kube-prometheus-stack` (Prometheus + Grafana + AlertManager)
3. `loki` (backend de logs)
4. `promtail` (agente de recolección de logs en cada nodo)
5. `grafana-tempo` (backend de trazas distribuidas)

### Endpoints de Acceso por Entorno

| Componente | Acceso Externo (VPS) | Acceso Interno (cluster DNS) |
|---|---|---|
| Prometheus | `<VPS_IP>:9090` | `prometheus-operated.observability:9090` |
| Grafana | `<VPS_IP>:3001` (admin / changeme) | `kube-prometheus-stack-grafana.observability:80` |
| Grafana Tempo (gRPC OTLP) | — (interno) | `tempo.observability.svc.cluster.local:4317` |
| Loki | — (interno) | `loki.observability:3100` |
| AlertManager | — (interno) | `alertmanager-operated.observability:9093` |

> **Nota de seguridad:** La contraseña de Grafana (`changeme`) debe ser rotada antes de exponer el puerto 3001 públicamente. En producción, la contraseña se inyecta desde Vault en tiempo de despliegue.

### Verificación del Stack

```bash
# Verificar Helm releases instalados
helm list -n observability

# Verificar Prometheus puede ser accedido
kubectl port-forward -n observability svc/prometheus-operated 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'

# Verificar Grafana
curl -s -u admin:changeme http://<VPS_IP>:3001/api/health | jq '.database'

# Verificar Tempo gRPC disponible
kubectl get svc -n observability | grep tempo
```

---

## 4. Instrumentación de Microservicios Spring Boot (Automática vía Scaffold)

### Principio de Diseño

Toda la instrumentación de observabilidad es **automática y no invasiva**. El scaffold (`maven_hexagonal_scaffold.py`) inyecta todas las dependencias, configuraciones y plantillas necesarias. Los desarrolladores de dominio no necesitan escribir ningún código relacionado con observabilidad.

### Dependencias Maven (pom.xml)

El scaffold añade las siguientes dependencias al bloque `<dependencies>` de cada microservicio Spring Boot:

```xml
<!-- Actuator — exposición de métricas y health checks -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>

<!-- Micrometer — registro de métricas en formato Prometheus -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>

<!-- Micrometer Tracing — bridge con OpenTelemetry -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>

<!-- OpenTelemetry OTLP Exporter — envío de trazas a Tempo -->
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>

<!-- Logstash Logback Encoder — logs estructurados en JSON -->
<dependency>
    <groupId>net.logstash.logback</groupId>
    <artifactId>logstash-logback-encoder</artifactId>
    <version>7.4</version>
</dependency>
```

### Configuración application.yml

El scaffold genera la siguiente sección de gestión en `src/main/resources/application.yml` de cada servicio:

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health, info, prometheus, metrics, env, loggers
  endpoint:
    health:
      show-details: always
      probes:
        enabled: true
  metrics:
    tags:
      application: ${spring.application.name}
      environment: ${spring.profiles.active:local}
    distribution:
      percentiles-histogram:
        http.server.requests: true
  tracing:
    sampling:
      probability: 1.0
```

### Configuración logback-spring.xml

El scaffold genera `src/main/resources/logback-spring.xml` con perfiles diferenciados:

**Perfil `dev` — salida por consola con traceId/spanId en patrón legible:**

```xml
<springProfile name="dev">
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{HH:mm:ss.SSS} [%thread] %-5level [%X{traceId},%X{spanId}] %logger{36} - %msg%n</pattern>
        </encoder>
    </appender>
    <root level="INFO">
        <appender-ref ref="CONSOLE"/>
    </root>
</springProfile>
```

**Perfil no-dev (local, staging, prod) — JSON estructurado para Loki:**

```xml
<springProfile name="!dev">
    <appender name="JSON_CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <includeMdcKeyName>traceId</includeMdcKeyName>
            <includeMdcKeyName>spanId</includeMdcKeyName>
            <customFields>{"service":"${spring.application.name}","environment":"${spring.profiles.active}"}</customFields>
        </encoder>
    </appender>
    <root level="INFO">
        <appender-ref ref="JSON_CONSOLE"/>
    </root>
</springProfile>
```

El puente Micrometer-OTEL propaga automáticamente `traceId` y `spanId` al MDC de SLF4J, por lo que todos los logs de una petición HTTP o mensaje Kafka comparten el mismo identificador de traza sin código adicional.

---

## 5. Instrumentación del ETL Spark/Scala (report-etl-service)

El `report-etl-service` es un CronJob de Kubernetes que ejecuta un job Spark. Su instrumentación difiere de los microservicios Spring Boot en los siguientes aspectos:

### OTEL Java Agent vía JAVA_TOOL_OPTIONS

El scaffold genera el manifiesto `k8s/cronjob.yaml` con la variable de entorno `JAVA_TOOL_OPTIONS` para inyectar el agente OTEL:

```yaml
env:
  - name: JAVA_TOOL_OPTIONS
    value: "-javaagent:/otel/opentelemetry-javaagent.jar"
  - name: OTEL_SERVICE_NAME
    value: "report-etl-service"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://tempo.observability.svc.cluster.local:4317"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "service.namespace=controlstock,deployment.environment=$(ENV)"
  - name: SPARK_MASTER
    value: "local[*]"
```

El init container `otel-agent` copia el agente desde `ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:latest` al volumen `emptyDir` montado en `/otel`, idéntico al patrón utilizado en los microservicios Spring Boot.

### Métricas Spark vía PrometheusServlet

El archivo `src/main/resources/spark-metrics.conf` generado por scaffold:

```properties
*.sink.prometheus.class=org.apache.spark.metrics.sink.PrometheusServlet
*.sink.prometheus.path=/metrics
*.source.jvm.class=org.apache.spark.metrics.source.JvmSource
driver.source.jvm.class=org.apache.spark.metrics.source.JvmSource
executor.source.jvm.class=org.apache.spark.metrics.source.JvmSource
```

Prometheus realiza scraping del endpoint `/metrics` del driver durante la ejecución del job.

### Logs Estructurados Spark

El scaffold genera `src/main/resources/logback-spark.xml` para el job Scala:

```xml
<configuration>
    <appender name="JSON_CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <customFields>{"service":"report-etl-service","type":"batch"}</customFields>
        </encoder>
    </appender>
    <root level="INFO">
        <appender-ref ref="JSON_CONSOLE"/>
    </root>
</configuration>
```

Promtail recolecta los logs del pod CronJob y los reenvía a Loki con las mismas etiquetas estructuradas que los microservicios Spring Boot, permitiendo correlacionar logs del ETL con eventos de dominio que los desencadenaron.

---

## 6. Modificaciones a los Helm Charts (Automáticas vía Scaffold)

### Generadas por maven_hexagonal_scaffold.py

El generador `maven_hexagonal_scaffold.py` produce modificaciones en los Helm charts de cada microservicio para integrar observabilidad de forma automática.

#### Anotaciones de Scraping Prometheus en deployment.yaml

El archivo `helm/<servicio>/templates/deployment.yaml` incluye las siguientes anotaciones en el bloque `spec.template.metadata.annotations`:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/path: "/actuator/prometheus"
  prometheus.io/port: "{{ .Values.service.port }}"
```

Estas anotaciones permiten al operador Prometheus del stack `kube-prometheus-stack` descubrir y realizar scraping del endpoint de métricas de cada pod automáticamente, sin necesidad de definir `ServiceMonitor` adicionales.

#### Init Container otel-agent

Cada `deployment.yaml` incluye un init container que descarga el agente OTEL antes de iniciar el contenedor principal:

```yaml
initContainers:
  - name: otel-agent
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:latest
    command: ["cp", "/javaagent.jar", "/otel/opentelemetry-javaagent.jar"]
    volumeMounts:
      - name: otel-agent-volume
        mountPath: /otel
volumes:
  - name: otel-agent-volume
    emptyDir: {}
```

El volumen `emptyDir` es compartido con el contenedor principal, que lo monta en `/otel`.

#### Variables de Entorno OTEL en el Contenedor Principal

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: "{{ .Values.app.name }}"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "{{ .Values.otel.collectorEndpoint }}"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "service.namespace=controlstock,deployment.environment={{ .Values.app.environment }}"
  - name: JAVA_TOOL_OPTIONS
    value: "-javaagent:/otel/opentelemetry-javaagent.jar"
volumeMounts:
  - name: otel-agent-volume
    mountPath: /otel
```

#### Valores por Entorno

**values-local.yaml y values-dev.yaml:**

```yaml
otel:
  collectorEndpoint: http://tempo.observability.svc.cluster.local:4317

app:
  environment: local
```

**values-prod.yaml:**

```yaml
otel:
  collectorEndpoint: http://tempo.observability.svc.cluster.local:4317

app:
  environment: prod
```

El endpoint de Tempo es idéntico en ambos entornos dado que el stack de observabilidad corre en K3s en los dos casos. La diferencia entre entornos queda capturada únicamente en el atributo `deployment.environment` de las trazas OTEL.

---

## 7. Dashboards y Alertas

### Dashboards Grafana — Importación

Los siguientes dashboards deben importarse en Grafana una vez el stack esté operativo. La importación puede realizarse via UI (Grafana → Dashboards → Import) o vía API:

```bash
# Importar dashboard JVM Micrometer (ID 4701)
curl -s -u admin:changeme -X POST \
  http://<VPS_IP>:3001/api/dashboards/import \
  -H "Content-Type: application/json" \
  -d '{"gnetId":4701,"overwrite":true,"inputs":[{"name":"DS_PROMETHEUS","type":"datasource","pluginId":"prometheus","value":"Prometheus"}]}'

# Importar dashboard Spring Boot Statistics (ID 12685)
curl -s -u admin:changeme -X POST \
  http://<VPS_IP>:3001/api/dashboards/import \
  -H "Content-Type: application/json" \
  -d '{"gnetId":12685,"overwrite":true,"inputs":[{"name":"DS_PROMETHEUS","type":"datasource","pluginId":"prometheus","value":"Prometheus"}]}'
```

| Dashboard | Grafana ID | Propósito |
|---|---|---|
| JVM Micrometer | 4701 | Heap, GC, threads, CPU por instancia de microservicio |
| Spring Boot Statistics | 12685 | HTTP request rate, error rate, P99 latency por endpoint |

### Reglas AlertManager

Las siguientes reglas de alerta se definen en `helm/kube-prometheus-stack/values.yaml` dentro del bloque `additionalPrometheusRulesMap`:

```yaml
additionalPrometheusRulesMap:
  controlstock-alerts:
    groups:
      - name: controlstock.http
        rules:
          - alert: HighErrorRate
            expr: |
              sum(rate(http_server_requests_seconds_count{status=~"5..",application=~".*controlstock.*"}[5m]))
              /
              sum(rate(http_server_requests_seconds_count{application=~".*controlstock.*"}[5m])) > 0.05
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "Tasa de error HTTP > 5% en {{ $labels.application }}"
              description: "La tasa de errores HTTP 5xx supera el umbral de 5% durante los últimos 5 minutos."

          - alert: HighP99Latency
            expr: |
              histogram_quantile(0.99,
                sum(rate(http_server_requests_seconds_bucket{application=~".*controlstock.*"}[5m])) by (le, application)
              ) > 2
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Latencia P99 > 2s en {{ $labels.application }}"
              description: "El percentil 99 de latencia HTTP supera 2 segundos durante los últimos 5 minutos."
```

### Integración Loki — Logs Estructurados

Loki indexa las siguientes etiquetas de los logs JSON producidos por LogstashEncoder:

| Etiqueta Loki | Campo JSON | Ejemplo |
|---|---|---|
| `service` | `service` | `catalog-service` |
| `environment` | `environment` | `prod` |
| `namespace` | Pod label | `controlstock` |
| `pod` | Pod name | `catalog-service-7d9f8c-xyz` |

Consulta LogQL de ejemplo para filtrar errores de un servicio específico con correlación de traza:

```logql
{service="inventory-service", environment="prod"} |= "ERROR"
| json
| line_format "{{.traceId}} {{.message}}"
```

### Integración Grafana Tempo — Trazas Distribuidas

Grafana Tempo recibe trazas en formato OTLP gRPC desde todos los microservicios. Para correlacionar una traza con sus logs:

1. En Grafana → Explore → seleccionar fuente de datos **Tempo**
2. Buscar por `traceId` (visible en logs de Loki)
3. Visualizar el span tree completo de la petición a través de todos los microservicios involucrados
4. Usar el botón "Logs for this span" para saltar a Loki con el filtro `{traceId="<id>"}`

La configuración de Grafana para correlación Tempo→Loki se define en `helm/kube-prometheus-stack/values.yaml`:

```yaml
grafana:
  additionalDataSources:
    - name: Tempo
      type: tempo
      url: http://tempo.observability.svc.cluster.local:3100
      jsonData:
        tracesToLogs:
          datasourceUid: loki
          filterByTraceID: true
          filterBySpanID: false
          lokiSearch: true
```

---

## 8. Terraform — Módulo `helm-observability/` (Ambos Entornos)

### Estructura Generada por base-infrastructure-builder.sh

```
terraform/modules/helm-observability/
├── variables.tf   # Variables de configuración del módulo
└── main.tf        # Recursos Helm para todo el stack de observabilidad
```

### variables.tf

```hcl
variable "grafana_admin_password" {
  description = "Contraseña del administrador de Grafana"
  type        = string
  sensitive   = true
}

variable "install_loki" {
  description = "Instalar Grafana Loki para centralización de logs"
  type        = bool
  default     = true
}

variable "install_tempo" {
  description = "Instalar Grafana Tempo para trazas distribuidas"
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace de Kubernetes para el stack de observabilidad"
  type        = string
  default     = "observability"
}

variable "prometheus_retention_days" {
  description = "Días de retención de métricas en Prometheus"
  type        = number
  default     = 15
}
```

### main.tf (resumen de recursos)

```hcl
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = var.namespace
  create_namespace = true

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "${var.prometheus_retention_days}d"
  }
}

resource "helm_release" "loki" {
  count      = var.install_loki ? 1 : 0
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  namespace  = var.namespace
  depends_on = [helm_release.kube_prometheus_stack]
}

resource "helm_release" "tempo" {
  count      = var.install_tempo ? 1 : 0
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  namespace  = var.namespace
  depends_on = [helm_release.kube_prometheus_stack]
}
```

### Invocación del Módulo en el Plan Principal

```hcl
# terraform/main.tf (fragmento)
module "helm_observability" {
  source = "./modules/helm-observability"

  grafana_admin_password    = var.grafana_admin_password
  install_loki              = true
  install_tempo             = true
  prometheus_retention_days = 15
}
```

---

## 9. Integración con CI/CD

### Verificación en el Pipeline Jenkins

El paso `runSmokeTests` de la shared library Jenkins verifica, además del health check estándar, que el endpoint de métricas Prometheus esté disponible:

```groovy
// Jenkinsfile (fragmento generado por scaffold)
stage('Smoke Tests') {
    steps {
        script {
            sharedLib.runSmokeTests([
                healthUrl: "http://${SERVICE_HOST}:${SERVICE_PORT}/actuator/health/readiness",
                prometheusUrl: "http://${SERVICE_HOST}:${SERVICE_PORT}/actuator/prometheus",
                expectedStatus: 200,
                retries: 5,
                delaySeconds: 10
            ])
        }
    }
}
```

La validación de `runSmokeTests` realiza las siguientes comprobaciones:

1. `GET /actuator/health/readiness` → HTTP 200 con `{"status":"UP"}`
2. `GET /actuator/prometheus` → HTTP 200 con contenido de tipo `text/plain` (métricas Prometheus)
3. Presencia de la métrica `jvm_memory_used_bytes` en la respuesta del endpoint Prometheus

Si alguna verificación falla, el pipeline marca el stage como FAILURE y ArgoCD no avanza al entorno siguiente.

### Verificación Post-Despliegue (ArgoCD)

Después de que ArgoCD completa el auto-sync de un servicio al entorno de producción:

1. **Verificar aparición en Prometheus targets:**
   ```bash
   curl -s http://<VPS_IP>:9090/api/v1/targets | \
     jq '.data.activeTargets[] | select(.labels.application=="<servicio>") | .health'
   # Debe retornar: "up"
   ```

2. **Verificar trazas en Grafana Tempo:**
   - Grafana → Explore → Tempo
   - Realizar una petición al servicio desplegado
   - Buscar por `service.name = "<servicio>"` en los últimos 5 minutos
   - Verificar que el span tree completo es visible

3. **Verificar logs en Loki:**
   - Grafana → Explore → Loki
   - Query: `{service="<servicio>", environment="prod"} | json | traceId != ""`
   - Confirmar que los logs contienen `traceId` y `spanId` en los campos JSON

---

## 10. Criterios de Aceptación

### Stack de Observabilidad

- [ ] `kubectl get pods -n observability` muestra todos los pods en estado `Running` (kube-prometheus-stack, loki, promtail, tempo)
- [ ] Grafana accesible en `<VPS_IP>:3001` con credenciales `admin/changeme`
- [ ] Prometheus accesible en `<VPS_IP>:9090` y mostrando la página de targets
- [ ] `helm list -n observability` lista los 4 releases: `kube-prometheus-stack`, `loki`, `loki-promtail`, `tempo`
- [ ] AlertManager operativo: `kubectl get alertmanager -n observability` muestra estado `True`

### Instrumentación de Microservicios

- [ ] Cada microservicio Spring Boot contiene las 5 dependencias de observabilidad en su `pom.xml` (actuator, micrometer-prometheus, micrometer-tracing-bridge-otel, opentelemetry-exporter-otlp, logstash-logback-encoder)
- [ ] Cada `application.yml` expone el endpoint `/actuator/prometheus` en la lista de endpoints habilitados
- [ ] Cada `logback-spring.xml` genera JSON estructurado con `traceId` y `spanId` en perfil no-dev
- [ ] El `deployment.yaml` de cada Helm chart contiene las 3 anotaciones de scraping Prometheus
- [ ] El init container `otel-agent` está definido en cada `deployment.yaml`
- [ ] Las variables de entorno OTEL (`OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `JAVA_TOOL_OPTIONS`) están presentes en cada `deployment.yaml`
- [ ] `values-local.yaml` y `values-prod.yaml` contienen `otel.collectorEndpoint: http://tempo.observability.svc.cluster.local:4317`

### Integración Operativa (tras despliegue de al menos un servicio)

- [ ] Prometheus muestra el target del servicio en estado `up` (scraping exitoso de `/actuator/prometheus`)
- [ ] Grafana Explore (Tempo) muestra trazas del servicio desplegado con span tree completo
- [ ] Grafana Explore (Loki) muestra logs JSON del servicio con campos `traceId` y `spanId` presentes
- [ ] Dashboard JVM Micrometer (ID 4701) importado y mostrando métricas de heap, GC y threads
- [ ] Dashboard Spring Boot Statistics (ID 12685) importado y mostrando request rate y latencia P99
- [ ] Reglas AlertManager configuradas para error rate > 5% y latencia P99 > 2s
- [ ] Pipeline Jenkins paso `runSmokeTests` verifica `/actuator/prometheus` con HTTP 200 exitoso
- [ ] Correlación Loki↔Tempo funcional: desde un log con `traceId` se puede navegar al span en Tempo
