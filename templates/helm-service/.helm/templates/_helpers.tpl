{{- define "svc.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* имя ресурсов = имя релиза Argo CD (origination, scoring, ...) */}}
{{- define "svc.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "svc.image" -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- if .Values.image.digest -}}
{{ .Values.image.repository }}:{{ $tag }}@{{ .Values.image.digest }}
{{- else -}}
{{ .Values.image.repository }}:{{ $tag }}
{{- end -}}
{{- end -}}

{{- define "svc.selectorLabels" -}}
app.kubernetes.io/name: {{ include "svc.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "svc.labels" -}}
{{ include "svc.selectorLabels" . }}
app.kubernetes.io/version: {{ default .Chart.AppVersion .Values.image.tag | quote }}
app.kubernetes.io/part-of: arba
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
arba.kz/tier: {{ .Values.global.tier | quote }}
arba.kz/env: {{ .Values.global.env | quote }}
{{- end -}}

{{- define "svc.podSecurity" -}}
securityContext:
  runAsNonRoot: true
  runAsUser: 65532
  runAsGroup: 65532
  seccompProfile:
    type: RuntimeDefault
{{- end -}}

{{- define "svc.containerSecurity" -}}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
{{- end -}}

{{- define "svc.env" -}}
- name: ARBA_ENV
  value: {{ .Values.global.env | quote }}
- name: POD_NAME
  valueFrom: { fieldRef: { fieldPath: metadata.name } }
- name: GOMEMLIMIT
  valueFrom: { resourceFieldRef: { resource: limits.memory, divisor: "1" } }
{{- $p := .Release.Name | upper | replace "-" "_" }}
{{- with .Values.platform }}
{{- if .natsUrl }}
- name: {{ $p }}_NATS_URL
  value: {{ .natsUrl | quote }}
{{- end }}
{{- if .otelEndpoint }}
- name: {{ $p }}_OTEL_ENDPOINT
  value: {{ .otelEndpoint | quote }}
{{- end }}
{{- with .jwt }}
{{- if .jwksUrl }}
- name: {{ $p }}_JWT_JWKS_URL
  value: {{ .jwksUrl | quote }}
- name: {{ $p }}_JWT_ISSUER
  value: {{ .issuer | quote }}
- name: {{ $p }}_JWT_AUDIENCE
  value: {{ .audience | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- if and .Values.database .Values.database.enabled }}
- name: {{ $p }}_DATABASE_DSN
  valueFrom:
    secretKeyRef: { name: {{ default (printf "%s-db" .Release.Name) .Values.database.secret }}, key: {{ default "dsn" .Values.database.key }} }
{{- end }}
{{- range $k, $v := .Values.env }}
- name: {{ $k }}
  value: {{ $v | quote }}
{{- end }}
{{- range .Values.secretEnv }}
- name: {{ .name }}
  valueFrom:
    secretKeyRef: { name: {{ .secret }}, key: {{ .key }} }
{{- end }}
{{- end -}}

{{- define "svc.envFrom" -}}
{{- range .Values.envFromSecrets }}
- secretRef: { name: {{ . }} }
{{- end }}
{{- end -}}
