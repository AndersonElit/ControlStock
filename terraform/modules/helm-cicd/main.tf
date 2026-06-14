resource "kubernetes_service_account" "jenkins" {
    metadata {
    name = "jenkins"
    namespace = "cicd"
  }
}
resource "kubernetes_cluster_role_binding" "jenkins" {
  metadata { name = "jenkins-cluster-admin" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.jenkins.metadata[0].name
    namespace = "cicd"
  }
}
resource "helm_release" "gitea" {
  name       = "gitea"
  repository = "https://dl.gitea.com/charts/"
  chart      = "gitea"
  version    = "10.4.0"
  namespace  = "cicd"
  wait       = true
  timeout    = 600
    # La imagen bitnami/redis-cluster fue purgada de Docker Hub; gitea no la
    # necesita en entorno local (usa cola/caché interna por defecto).
    set {
    name = "redis-cluster.enabled"
    value = "false"
  }
    set {
    name = "redis.enabled"
    value = "false"
  }
    set {
    name = "gitea.admin.username"
    value = "gitea_admin"
  }
    set_sensitive {
    name = "gitea.admin.password"
    value = var.gitea_admin_password
  }
    set {
    name = "gitea.admin.email"
    value = "admin@${var.project}.local"
  }
    set {
    name = "postgresql.enabled"
    value = "false"
  }
    set {
    name = "postgresql-ha.enabled"
    value = "false"
  }
    set {
    name = "gitea.config.database.DB_TYPE"
    value = "postgres"
  }
    set {
    name = "gitea.config.database.HOST"
    value = "postgresql.data.svc.cluster.local:5432"
  }
    set {
    name = "gitea.config.database.NAME"
    value = "gitea"
  }
    set {
    name = "gitea.config.database.USER"
    value = "postgres"
  }
    set_sensitive {
    name = "gitea.config.database.PASSWD"
    value = var.pg_admin_password
  }
    set {
    name = "gitea.config.server.DOMAIN"
    value = var.vm_ip
  }
    set {
    name = "gitea.config.server.ROOT_URL"
    value = "http://${var.vm_ip}:3000"
  }
    set {
    name = "gitea.config.packages.ENABLED"
    value = "true"
  }
    set {
    name = "service.http.type"
    value = "NodePort"
  }
    set {
    name = "service.http.nodePort"
    value = "3000"
  }
    set {
    name = "persistence.size"
    value = "5Gi"
  }
}
resource "helm_release" "jenkins" {
  name       = "jenkins"
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  version    = "5.9.25"
  namespace  = "cicd"
  wait       = true
  timeout    = 600
  depends_on = [kubernetes_service_account.jenkins]
    # Usa el ServiceAccount creado por Terraform (con el ClusterRoleBinding
    # cluster-admin) en lugar de que el chart cree uno propio.
    set {
    name = "serviceAccount.create"
    value = "false"
  }
    set {
    name = "serviceAccount.name"
    value = "jenkins"
  }
    set {
    name = "controller.serviceType"
    value = "NodePort"
  }
    set {
    name = "controller.serviceNodePort"
    value = "8080"
  }
    set {
    name = "controller.admin.username"
    value = "admin"
  }
    set_sensitive {
    name = "controller.admin.password"
    value = var.jenkins_admin_password
  }
    set {
    name = "persistence.size"
    value = "5Gi"
  }
    set {
    name = "controller.resources.requests.memory"
    value = "512Mi"
  }
    set {
    name = "controller.resources.requests.cpu"
    value = "250m"
  }
    set {
    name = "controller.installPlugins[0]"
    value = "kubernetes"
  }
}
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.5.21"
  namespace  = "cicd"
  wait       = true
  timeout    = 600
    set {
    name = "server.service.type"
    value = "NodePort"
  }
    set {
    name = "server.service.nodePortHttp"
    value = "8081"
  }
    set {
    name = "server.extraArgs[0]"
    value = "--insecure"
  }
    set {
    name = "repoServer.resources.requests.memory"
    value = "128Mi"
  }
    set {
    name = "configs.params.server\\.insecure"
    value = "true"
  }
}
# AppProject — sustituye __PROJECT__ y __VM_IP__ via sed
resource "null_resource" "argocd_appproject" {
  depends_on = [helm_release.argocd]
  provisioner "local-exec" {
    command = <<-CMD
      sleep 15
      sed -e 's/__PROJECT__/${var.project}/g' \
          -e 's/__VM_IP__/${var.vm_ip}/g' \
          '${path.module}/argocd-appproject.yaml.tpl' \
      | kubectl --kubeconfig='${var.kubeconfig_path}' apply -f -
    CMD
  }
    triggers = {
    project = var.project
    argocd_v = helm_release.argocd.version
  }
}
# ApplicationSet — Git generator: auto-descubre servicios desde charts/ en helm-charts repo
resource "null_resource" "argocd_applicationset" {
  depends_on = [null_resource.argocd_appproject]
  provisioner "local-exec" {
    command = <<-CMD
      sed -e 's/__PROJECT__/${var.project}/g' \
          -e 's/__VM_IP__/${var.vm_ip}/g' \
          -e 's/__ENV__/${var.env}/g' \
          '${path.module}/argocd-applicationset.yaml.tpl' \
      | kubectl --kubeconfig='${var.kubeconfig_path}' apply -f -
    CMD
  }
    triggers = {
    project = var.project
    env = var.env
    argocd_v = helm_release.argocd.version
  }
}
