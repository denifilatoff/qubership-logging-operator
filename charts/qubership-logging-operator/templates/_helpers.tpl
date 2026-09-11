{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "fluentd.name" -}}
  {{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "fluentd.fullname" -}}
  {{- if .Values.fullnameOverride -}}
    {{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
  {{- else -}}
    {{- $name := default .Chart.Name .Values.nameOverride -}}
    {{- if contains $name .Release.Name -}}
      {{- .Release.Name | trunc 63 | trimSuffix "-" -}}
    {{- else -}}
      {{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "fluentd.chart" -}}
  {{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Base resource labels: pass full chart context as ., or dict with "ctx" and optional "name" / "component". */}}
{{- define "logging.labels" -}}
{{- $ctx := index . "ctx" | default . -}}
{{- $vals := $ctx.Values -}}
{{- $name := .name | default $vals.name -}}
{{- $component := .component | default $ctx.Chart.Name -}}
name: {{ $name }}
app.kubernetes.io/name: {{ $name }}
app.kubernetes.io/component: {{ $component }}
app.kubernetes.io/part-of: logging-service
app.kubernetes.io/managed-by: {{ $ctx.Release.Service }}
{{- end -}}

{{- define "logging.extraLabels" -}}
{{- $ctx := index . "ctx" | default . -}}
{{- $vals := $ctx.Values -}}
{{- $extra := .extraLabels | default ($vals.labels | default dict) -}}
{{- with $extra }}

{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "helm-chart.serviceAccountName" -}}
  {{- if .Values.serviceAccount.create -}}
    {{ default (include "helm-chart.fullname" .) .Values.serviceAccount.name }}
  {{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
  {{- end -}}
{{- end -}}

{{/*
Check the major version of Graylog and return 'true' if it equal 5
*/}}
{{- define "graylog.isMajorVersion5" -}}
  {{- if regexMatch "^*:5\\.[0-9]+\\.[0-9]+(@sha256:[a-f0-9]{64})?$" (include "graylog.image" . ) -}}
true
  {{- end -}}
{{- end -}}

{{/*
Return true if generateCerts in TLS is enabled for Graylog HTTP.
*/}}
{{- define "graylog.http.generateCerts.enabled" -}}
  {{- if .Values.graylog.install -}}
    {{- if .Values.graylog.tls -}}
      {{- if .Values.graylog.tls.http -}}
        {{- if .Values.graylog.tls.http.generateCerts -}}
          {{- if .Values.graylog.tls.http.generateCerts.enabled -}}
true
          {{- end -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return true if generateCerts in TLS is enabled for Graylog input.
*/}}
{{- define "graylog.input.generateCerts.enabled" -}}
  {{- if .Values.graylog.install -}}
    {{- if .Values.graylog.tls -}}
      {{- if .Values.graylog.tls.input -}}
        {{- if .Values.graylog.tls.input.generateCerts -}}
          {{- if .Values.graylog.tls.input.generateCerts.enabled -}}
true
          {{- end -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return true if generateCerts in TLS is enabled for Fluentd.
*/}}
{{- define "fluentd.generateCerts.enabled" -}}
  {{- if .Values.fluentd.install -}}
    {{- if .Values.fluentd.tls -}}
      {{- if .Values.fluentd.tls.generateCerts -}}
        {{- if .Values.fluentd.tls.generateCerts.enabled -}}
true
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return true if generateCerts in TLS is enabled for Fluent-bit.
*/}}
{{- define "fluentbit.generateCerts.enabled" -}}
  {{- if .Values.fluentbit.install -}}
    {{- if .Values.fluentbit.tls -}}
      {{- if .Values.fluentbit.tls.generateCerts -}}
        {{- if .Values.fluentbit.tls.generateCerts.enabled -}}
true
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return true if generateCerts in TLS is enabled for Fluent-bit aggregator.
*/}}
{{- define "fluentbit.aggregator.generateCerts.enabled" -}}
  {{- if .Values.fluentbit.install -}}
    {{- if .Values.fluentbit.aggregator -}}
      {{- if .Values.fluentbit.aggregator.install -}}
        {{- if .Values.fluentbit.aggregator.tls -}}
          {{- if .Values.fluentbit.aggregator.tls.generateCerts -}}
            {{- if .Values.fluentbit.aggregator.tls.generateCerts.enabled -}}
true
            {{- end -}}
          {{- end -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return true if cacerts for HTTP TLS in Graylog is present and mounted.
*/}}
{{- define "graylog.cacerts.present" -}}
  {{- if .Values.graylog.tls.http.cacerts -}}
true
  {{- else -}}
    {{- if ( include "graylog.http.generateCerts.enabled" . ) -}}
true
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return true if cert for HTTP TLS in Graylog is present and mounted.
*/}}
{{- define "graylog.cert.present" -}}
  {{- if .Values.graylog.tls.http.cert -}}
    {{- if and .Values.graylog.tls.http.cert.secretName .Values.graylog.tls.http.cert.secretKey }}
true
    {{- else -}}
      {{- if ( include "graylog.http.generateCerts.enabled" . ) -}}
true
      {{- end -}}
    {{- end -}}
  {{- else -}}
    {{- if ( include "graylog.http.generateCerts.enabled" . ) -}}
true
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return true if key for HTTP TLS in Graylog is present and mounted.
*/}}
{{- define "graylog.key.present" -}}
  {{- if .Values.graylog.tls.http.key -}}
    {{- if and .Values.graylog.tls.http.key.secretName .Values.graylog.tls.http.key.secretKey }}
true
    {{- else -}}
      {{- if (include "graylog.http.generateCerts.enabled" . ) -}}
true
      {{- end -}}
    {{- end -}}
  {{- else -}}
    {{- if (include "graylog.http.generateCerts.enabled" . ) -}}
true
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Set default value for graylog host if not specified in Values.
*/}}
{{- define "graylog.host" -}}
  {{- if .Values.graylog.install -}}
    {{- if not .Values.graylog.host -}}
      {{- if .Values.CLOUD_PUBLIC_HOST -}}
        {{- printf "%s-%s.%s/" "https://graylog" .Values.NAMESPACE (trimSuffix "/" .Values.CLOUD_PUBLIC_HOST) -}}
      {{- end -}}
    {{- else -}}
      {{- $host := trimSuffix "/" .Values.graylog.host -}}
      {{- printf "%s/" $host -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return secretName if generateCerts in TLS is enabled for Graylog input.
*/}}
{{- define "graylog.secretName" -}}
  {{- if .Values.graylog.install -}}
    {{- if .Values.graylog.tls -}}
      {{- if .Values.graylog.tls.input -}}
        {{- if .Values.graylog.tls.input.cert -}}
            {{- printf "%s" (trimSuffix "/" .Values.graylog.tls.input.cert.secretName) -}}
        {{- else -}}
          {{- if .Values.graylog.tls.input.generateCerts -}}
            {{- if .Values.graylog.tls.input.generateCerts.enabled -}}
              {{- printf "%s" (trimSuffix "/" .Values.graylog.tls.input.generateCerts.secretName) -}}
            {{- end -}}
          {{- end -}}
        {{- end -}}
      {{- end -}}
      {{- if .Values.graylog.tls.http -}}
        {{- if .Values.graylog.tls.http.cert -}}
          {{- printf "%s" (trimSuffix "/" .Values.graylog.tls.http.cert.secretName) -}}
        {{- else -}}
          {{- if .Values.graylog.tls.http.generateCerts -}}
            {{- if .Values.graylog.tls.http.generateCerts.enabled -}}
              {{- printf "%s" (trimSuffix "/" .Values.graylog.tls.http.generateCerts.secretName) -}}
            {{- end -}}
          {{- end -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}


{{- define "logging.monitoredImages" -}}
{{- end -}}

{{/******************************************************************************************************************/}}

{{/*
Find a logging-operator image in various places.
Image can be found from:
* specified by user from .Values.operatorImage
* default value
*/}}
{{- define "logging-operator.image" -}}
  {{- if .Values.operatorImage -}}
    {{- printf "%s" .Values.operatorImage -}}
  {{- else -}}
    {{- print "ghcr.io/netcracker/qubership-logging-operator:main" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a graylog image in various places.
Image can be found from:
* specified by user from .Values.operatorImage
* default value
*/}}
{{- define "graylog.image" -}}
  {{- if .Values.graylog.dockerImage -}}
    {{- printf "%s" .Values.graylog.dockerImage -}}
  {{- else -}}
    {{- /* # renovate: datasource=docker depName=graylog/graylog */ -}}
    {{- print "docker.io/graylog/graylog:5.2.12@sha256:3f4aa0885cd3e30442e5f7e1b2361f57773831bb84515386eb5dfa6f426fc1d7" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a fluentd image in various places.
Image can be found from:
* specified by user from .Values.fluentd.dockerImage
* default value
*/}}
{{- define "fluentd.image" -}}
  {{- if .Values.fluentd.dockerImage -}}
    {{- printf "%s" .Values.fluentd.dockerImage -}}
  {{- else -}}
    {{- /* # renovate: datasource=github-releases depName=Netcracker/qubership-fluentd versioning=loose */ -}}
    {{- print "ghcr.io/netcracker/qubership-fluentd:1.19.3-2" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a Fluentd ConfigMap reload image in various places.
Image can be found from:
* specified by user from Values.fluentd.configmapReload.image
* default value
*/}}
{{- define "fluentd.configmapReload.image" -}}
  {{- if .Values.fluentd.configmapReload.dockerImage -}}
    {{- printf "%s" .Values.fluentd.configmapReload.dockerImage -}}
  {{- else -}}
    {{- /* # renovate: datasource=github-releases depName=jimmidyson/configmap-reload versioning=semver */ -}}
    {{- print "ghcr.io/jimmidyson/configmap-reload:v0.15.0" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a FluentBit image in various places.
Image can be found from:
* specified by user from .Values.fluentbit.dockerImage
* default value
*/}}
{{- define "fluentbit.image" -}}
  {{- if .Values.fluentbit.dockerImage -}}
    {{- printf "%s" .Values.fluentbit.dockerImage -}}
  {{- else -}}
    {{- /* # renovate: datasource=docker depName=fluent/fluent-bit */ -}}
    {{- print "docker.io/fluent/fluent-bit:5.1.1" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a FluentBit ConfigMap reload image in various places.
Image can be found from:
* specified by user from .Values.fluentbit.configmapReload.dockerImage
* default value
*/}}
{{- define "fluentbit.configmapReload.image" -}}
  {{- if .Values.fluentbit.configmapReload.dockerImage -}}
    {{- printf "%s" .Values.fluentbit.configmapReload.dockerImage -}}
  {{- else -}}
    {{- /* # renovate: datasource=github-releases depName=jimmidyson/configmap-reload versioning=semver */ -}}
    {{- print "ghcr.io/jimmidyson/configmap-reload:v0.15.0" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a cloud-events-reader image in various places.
Image can be found from:
* specified by user from .Values.cloudEventsReader.dockerImage
* default value
*/}}
{{- define "cloud-events-reader.image" -}}
  {{- if .Values.cloudEventsReader.dockerImage -}}
    {{- printf "%s" .Values.cloudEventsReader.dockerImage -}}
  {{- else -}}
    {{- /* # renovate: datasource=github-releases depName=Netcracker/qubership-kube-events-reader versioning=semver */ -}}
    {{- print "ghcr.io/netcracker/qubership-kube-events-reader:2.9.4" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a logging-integration-tests image in various places.
Image can be found from:
* specified by user from .Values.integrationTests.image
* default value
*/}}
{{- define "logging-integration-tests.image" -}}
  {{- if .Values.integrationTests.image -}}
    {{- printf "%s" .Values.integrationTests.image -}}
  {{- else -}}
    {{- print "ghcr.io/netcracker/qubership-logging-integration-tests:main" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a graylog-plugins-init-container image in various places.
Image can be found from:
* specified by user from .Values.graylog.initContainerDockerImage
* default value
*/}}
{{- define "graylog-plugins-init.image" -}}
  {{- if .Values.graylog.initContainerDockerImage -}}
    {{- printf "%s" .Values.graylog.initContainerDockerImage -}}
  {{- else -}}
    {{- /* # renovate: datasource=github-releases depName=Netcracker/qubership-graylog-plugins-init versioning=semver */ -}}
    {{- print "ghcr.io/netcracker/qubership-graylog-plugins-init:0.1.0" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a mongodb image in various places.
Image can be found from:
* specified by user from .Values.graylog.mongodbImage
* default value
*/}}
{{- define "mongodb.image" -}}
  {{- if .Values.graylog.mongodbImage -}}
    {{- printf "%s" .Values.graylog.mongodbImage -}}
  {{- else -}}
    {{- /* # renovate: datasource=docker depName=mongo */ -}}
    {{- print "docker.io/mongo:5.0.33@sha256:41108d183e972dcbf98d09ed83f6cfc89a471a3f15d06f9d64a95e45d9db8dd2" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a authProxy image in various places.
Image can be found from:
* specified by user from .Values.graylog.authProxy.image
* default value
*/}}
{{- define "authProxy.image" -}}
  {{- if .Values.graylog.authProxy.image -}}
    {{- printf "%s" .Values.graylog.authProxy.image -}}
  {{- else -}}
    {{- /* # renovate: datasource=github-releases depName=Netcracker/qubership-graylog-auth-proxy versioning=semver */ -}}
    {{- print "ghcr.io/netcracker/qubership-graylog-auth-proxy:0.2.3" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a init_setup image in various places.
Image can be found from:
* specified by user from .Values.graylog.initSetupImage
* default value
*/}}
{{- define "init-setup.image" -}}
  {{- if .Values.graylog.initSetupImage -}}
    {{- printf "%s" .Values.graylog.initSetupImage -}}
  {{- else -}}
    {{- /* # renovate: datasource=docker depName=alpine */ -}}
    {{- print "docker.io/alpine:3.24.1" -}}
  {{- end -}}
{{- end -}}

{{/*
MongoDB images for sequential upgrades.
Upgrade path:
3.6.23 -> 4.0.28 -> 4.2.22 -> 4.4.17 -> 5.0.19
*/}}

{{/*
MongoDB 4.0 image.
*/}}
{{- define "mongodb40.image" -}}
  {{- if .Values.graylog.mongodb40Image -}}
    {{- printf "%s" .Values.graylog.mongodb40Image -}}
  {{- else -}}
    {{- /* # renovate: datasource=docker depName=mongo */ -}}
    {{- print "docker.io/mongo:4.0.28@sha256:4ca81c89ad08f4cfa9906005126112bffe8fb363800466ef5e50f6238f6f6af1" -}}
  {{- end -}}
{{- end -}}

{{/*
MongoDB 4.2 image.
*/}}
{{- define "mongodb42.image" -}}
  {{- if .Values.graylog.mongodb42Image -}}
    {{- printf "%s" .Values.graylog.mongodb42Image -}}
  {{- else -}}
    {{- /* # renovate: datasource=docker depName=mongo */ -}}
    {{- print "docker.io/mongo:4.2.24@sha256:699d652ed67423d689258bad7b316cf005dfbb82b334118ec306f049042f3717" -}}
  {{- end -}}
{{- end -}}

{{/*
MongoDB 4.4 image.
*/}}
{{- define "mongodb44.image" -}}
  {{- if .Values.graylog.mongodb44Image -}}
    {{- printf "%s" .Values.graylog.mongodb44Image -}}
  {{- else -}}
    {{- /* # renovate: datasource=docker depName=mongo */ -}}
    {{- print "docker.io/mongo:4.4.30@sha256:4be76f674fc4b27859816811b8baa3c51830eb1dbf4ca81a51e26b79edd662ef" -}}
  {{- end -}}
{{- end -}}

{{/*
Return the secret name for output auth credentials.
Accepts a dict with "auth" (the auth config) and "default" (default secret name).
*/}}
{{- define "logging.output.auth.secretName" -}}
  {{- if and .auth.credentials .auth.credentials.secretName -}}
    {{- .auth.credentials.secretName -}}
  {{- else -}}
    {{- .default -}}
  {{- end -}}
{{- end -}}

{{/*
Check if output auth credentials should create a secret.
Returns "true" if credentials are set AND no explicit secret refs override them.
Accepts a dict with "auth" (the auth config).
*/}}
{{- define "logging.output.auth.shouldCreateSecret" -}}
  {{- if .auth.credentials -}}
    {{- $hasTokenRef := and .auth.token .auth.token.name .auth.token.key -}}
    {{- $hasUserRef := and .auth.user .auth.user.name .auth.user.key .auth.password .auth.password.name .auth.password.key -}}
    {{- if not (or $hasTokenRef $hasUserRef) -}}
      {{- if or .auth.credentials.token (and .auth.credentials.username .auth.credentials.password) -}}
true
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Render the CRD-compatible auth block for Loki outputs.
Accepts a dict with "auth" (the auth config) and "default" (default secret name).
*/}}
{{- define "logging.output.auth" -}}
  {{- if .auth.token -}}
    {{- if and .auth.token.name .auth.token.key }}
auth:
  token:
    name: {{ .auth.token.name }}
    key: {{ .auth.token.key }}
    {{- end -}}
  {{- else if and .auth.user .auth.password -}}
    {{- if and .auth.user.name .auth.user.key .auth.password.name .auth.password.key }}
auth:
  user:
    name: {{ .auth.user.name }}
    key: {{ .auth.user.key }}
  password:
    name: {{ .auth.password.name }}
    key: {{ .auth.password.key }}
    {{- end -}}
  {{- else if .auth.credentials -}}
    {{- $secretName := include "logging.output.auth.secretName" . -}}
    {{- if .auth.credentials.token }}
auth:
  token:
    name: {{ $secretName }}
    key: token
    {{- else if and .auth.credentials.username .auth.credentials.password }}
auth:
  user:
    name: {{ $secretName }}
    key: username
  password:
    name: {{ $secretName }}
    key: password
    {{- end -}}
  {{- end -}}
{{- end -}}
