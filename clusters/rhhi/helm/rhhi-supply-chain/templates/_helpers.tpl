{{/*
Expand ECR image reference with registry URL and prefix.
*/}}
{{- define "rhhi.ecrImage" -}}
{{- $registry := required "global.ecrRegistryUrl is required" .Values.global.ecrRegistryUrl -}}
{{- $prefix := .Values.global.ecrRepositoryPrefix -}}
{{- $image := . -}}
{{ printf "%s/%s/%s" $registry $prefix $image }}
{{- end }}
