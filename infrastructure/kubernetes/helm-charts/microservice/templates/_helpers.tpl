{{/*
Fully qualified app name — equals release name (e.g. "storage-service")
*/}}
{{- define "microservice.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Chart label
*/}}
{{- define "microservice.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}

{{/*
Common labels applied to every resource
*/}}
{{- define "microservice.labels" -}}
helm.sh/chart: {{ include "microservice.chart" . }}
app.kubernetes.io/name: {{ include "microservice.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels used by Deployment and Service
*/}}
{{- define "microservice.selectorLabels" -}}
app: {{ include "microservice.fullname" . }}
{{- end }}

{{/*
ServiceAccount name — uses values.serviceAccount.name if set, otherwise release name
*/}}
{{- define "microservice.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else }}
{{- include "microservice.fullname" . }}
{{- end }}
{{- end }}

{{/*
Kubernetes FQDN for Istio host references
*/}}
{{- define "microservice.fqdn" -}}
{{- printf "%s.%s.svc.cluster.local" (include "microservice.fullname" .) .Values.namespace }}
{{- end }}

{{/*
Deployment name includes image tag to support multiple versions side-by-side (canary)
Dots in tag are replaced with dashes to produce a valid k8s name.
Example: storage-service-v1-0
*/}}
{{- define "microservice.deploymentName" -}}
{{- printf "%s-%s" (include "microservice.fullname" .) (.Values.image.tag | replace "." "-") }}
{{- end }}