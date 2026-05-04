{{/*
Common defaults for every Application produced by this chart.
*/}}
{{- define "platformApps.appMetadata" -}}
namespace: argocd
finalizers:
  - resources-finalizer.argocd.argoproj.io
{{- end -}}

{{- define "platformApps.syncPolicy" -}}
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
{{- end -}}
