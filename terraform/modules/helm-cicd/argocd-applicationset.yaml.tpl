apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: __PROJECT__-services
  namespace: cicd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - git:
        repoURL: 'http://__VM_IP__:3000/__PROJECT__/__PROJECT__-helm-charts.git'
        revision: main
        directories:
          - path: 'charts/*'
  template:
    metadata:
      name: '__PROJECT__-{{.path.basename}}'
    spec:
      project: __PROJECT__
      source:
        repoURL: 'http://__VM_IP__:3000/__PROJECT__/__PROJECT__-helm-charts.git'
        targetRevision: main
        path: '{{.path.path}}'
        helm:
          valueFiles:
            - values-__ENV__.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: apps
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
        retry:
          limit: 3
          backoff:
            duration: 10s
            factor: 2
