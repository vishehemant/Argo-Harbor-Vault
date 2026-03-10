{{/*
Common labels
*/}}
{{- define "sample-web.labels" -}}
app: {{ .Chart.Name }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
environment: {{ .Values.environment }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "sample-web.selectorLabels" -}}
app: {{ .Chart.Name }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
