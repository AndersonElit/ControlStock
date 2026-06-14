apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: __PROJECT__
  namespace: cicd
spec:
  description: "Project __PROJECT__"
  sourceRepos:
    - 'http://__VM_IP__:3000/__PROJECT__/*'
  destinations:
    - namespace: apps
      server: https://kubernetes.default.svc
    - namespace: infra
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
