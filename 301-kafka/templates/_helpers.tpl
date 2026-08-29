{{/*
브로커 bootstrap 주소(클러스터 안) — bootstrap Service <kafka.name>.<ns>.svc.cluster.local:<clientPort>.
이 차트 안에서 브로커 주소가 필요한 곳(도구 3종의 롤아웃 checksum·토픽 Job)은 전부 이 헬퍼를 쓴다.
300-data-layer-base 의 global.kafkaBootstrap 은 이 값의 복사본이다(같은 커밋 규칙).
*/}}
{{- define "kafka.bootstrap" -}}
{{- printf "%s.%s.svc.cluster.local:%d" .Values.kafka.name .Values.global.namespace (int .Values.kafka.ports.client) -}}
{{- end -}}

{{/*
브로커 bootstrap 주소(클러스터 밖) — hostNetwork 라 노드 IP:클라이언트 포트 그대로. nodes 표 전부를 나열한다.
*/}}
{{- define "kafka.bootstrapExternal" -}}
{{- $l := list -}}
{{- range .Values.kafka.nodes }}{{ $l = append $l (printf "%s:%d" .ip (int $.Values.kafka.ports.client)) }}{{ end -}}
{{- join "," $l -}}
{{- end -}}

{{/*
controller.quorum.voters — nodes 표의 앞 controllers 개: "<id>@<ip>:<controllerPort>,…". 정적 쿼럼이라 전 브로커에 같은 값.
*/}}
{{- define "kafka.quorumVoters" -}}
{{- $l := list -}}
{{- range $i, $n := .Values.kafka.nodes }}{{ if lt $i (int $.Values.kafka.controllers) }}{{ $l = append $l (printf "%d@%s:%d" $i $n.ip (int $.Values.kafka.ports.controller)) }}{{ end }}{{ end -}}
{{- join "," $l -}}
{{- end -}}
