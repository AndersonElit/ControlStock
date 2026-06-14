locals {
  namespaces = ["infra","identity","secrets","data","messaging","cicd","observability","gateway","serverless","serverless-fn","apps"]
}
resource "kubernetes_namespace" "ns" {
  for_each = toset(local.namespaces)
  metadata {
    name   = each.value
    labels = { "managed-by" = "terraform" }
  }
  lifecycle { ignore_changes = [metadata[0].annotations] }
}
