resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.1.3"
  namespace  = "observability"
  wait       = true
  timeout    = 600
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "7d"
  }
  set {
    name  = "prometheus.service.type"
    value = "NodePort"
  }
  set {
    name  = "prometheus.service.nodePort"
    value = "9090"
  }
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
  set {
    name  = "grafana.service.type"
    value = "NodePort"
  }
  set {
    name  = "grafana.service.nodePort"
    value = "3001"
  }
  set {
    name  = "grafana.persistence.enabled"
    value = "true"
  }
  set {
    name  = "grafana.persistence.size"
    value = "2Gi"
  }
  set {
    name = "defaultRules.create"
    value = "true"
  }
}
  values = [<<-YAML
    grafana:
      additionalDataSources:
        - name: Loki
          type: loki
          uid: loki
          url: http://loki.observability.svc.cluster.local:3100
          access: proxy
          isDefault: false
          editable: true
        - name: Tempo
          type: tempo
          uid: tempo
          url: http://tempo.observability.svc.cluster.local:3100
          access: proxy
          isDefault: false
          editable: true
          jsonData:
            tracesToLogs:
              datasourceUid: loki
              filterByTraceID: true
              filterBySpanID: false
              lokiSearch: true
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
                  description: "La tasa de errores HTTP 5xx supera el umbral de 5% durante los ultimos 5 minutos."
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
                  description: "El percentil 99 de latencia HTTP supera 2 segundos durante los ultimos 5 minutos."
  YAML
  ]
}
resource "helm_release" "loki" {
  count      = var.install_loki ? 1 : 0
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.5.2"
  namespace  = "observability"
  wait       = true
  timeout    = 300
  values = [<<-YAML
    deploymentMode: SingleBinary
    loki:
      useTestSchema: true
      commonConfig:
        replication_factor: 1
      storage:
        type: filesystem
    singleBinary:
      replicas: 1
      persistence:
        size: 5Gi
    read:
      replicas: 0
    write:
      replicas: 0
    backend:
      replicas: 0
    # Los cachés memcached piden demasiada RAM para una VM single-node y
    # quedan en Pending (Insufficient memory), agotando el timeout de Helm.
    chunksCache:
      enabled: false
    resultsCache:
      enabled: false
  YAML
  ]
}
resource "helm_release" "promtail" {
  count      = var.install_loki ? 1 : 0
  depends_on = [helm_release.loki]
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.15.5"
  namespace  = "observability"
  wait       = true
  timeout    = 180
  set {
    name  = "config.lokiAddress"
    value = "http://loki:3100/loki/api/v1/push"
  }
}
resource "helm_release" "tempo" {
  count      = var.install_tempo ? 1 : 0
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = "1.9.0"
  namespace  = "observability"
  wait       = true
  timeout    = 300
  values = [<<-YAML
    tempo:
      storage:
        trace:
          backend: local
          local:
            path: /var/tempo/traces
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: "0.0.0.0:4317"
            http:
              endpoint: "0.0.0.0:4318"
    persistence:
      enabled: true
      size: 5Gi
  YAML
  ]
}
