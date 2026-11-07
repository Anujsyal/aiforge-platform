{{- define "ai-app.name" -}}
{{- required "appName is required" .Values.appName | trunc 40 | trimSuffix "-" -}}
{{- end -}}

{{- define "ai-app.team" -}}
{{- required "team is required" .Values.team -}}
{{- end -}}

{{/* Common labels BINA app.kubernetes.io/name (ingest job pods Service selector mein na aayein) */}}
{{- define "ai-app.commonLabels" -}}
app.kubernetes.io/part-of: aiforge
app.kubernetes.io/managed-by: {{ .Release.Service }}
aiforge.io/team: {{ include "ai-app.team" . }}
aiforge.io/cost-center: {{ .Values.costCenter | default (include "ai-app.team" .) }}
aiforge.io/app-type: rag
{{- end -}}

{{- define "ai-app.labels" -}}
app.kubernetes.io/name: {{ include "ai-app.name" . }}
{{ include "ai-app.commonLabels" . }}
{{- end -}}

{{- define "ai-app.selector" -}}
app.kubernetes.io/name: {{ include "ai-app.name" . }}
{{- end -}}

{{- define "ai-app.image" -}}
{{- $repo := required "image.repository is required" .Values.image.repository -}}
{{- if .Values.image.digest -}}
{{ $repo }}:{{ .Values.image.tag | default "pinned" }}@{{ .Values.image.digest }}
{{- else -}}
{{ $repo }}:{{ required "image.tag or image.digest is required" .Values.image.tag }}
{{- end -}}
{{- end -}}

{{- define "ai-app.basePath" -}}
{{ .Values.ingress.pathPrefix }}/{{ include "ai-app.name" . }}
{{- end -}}

{{- define "ai-app.vaultPath" -}}
{{ .Values.secrets.vaultPath | default (printf "teams/%s/%s" (include "ai-app.team" .) (include "ai-app.name" .)) }}
{{- end -}}

{{/* Restricted PSA ke liye container securityContext (sab containers pe same) */}}
{{- define "ai-app.containerSecurity" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
runAsNonRoot: true
runAsUser: 10001
capabilities:
  drop: ["ALL"]
seccompProfile:
  type: RuntimeDefault
{{- end -}}
