{{/*
Kafka Broker Bootstrap 주소를 생성한다.

- 모든 Broker의 Node IP:Client Port를 쉼표로 연결
- Broker가 hostNetwork를 사용하므로 광고 주소와 동일한 Node IP를 사용
- Broker 장애 시 클라이언트는 다음 Bootstrap 주소로 연결 시도
- 300-data-layer-base와 동일한 global.kafka.brokers를 원본으로 사용
  → Bootstrap 주소가 차트 간 불일치하지 않음
*/}}
{{- define "kafka.bootstrap" -}}
{{- $port := int .Values.global.kafka.ports.client -}}
{{- $l := list -}}
{{- range .Values.global.kafka.brokers }}
{{- $l = append $l (printf "%s:%d" .ip $port) }}
{{- end -}}
{{- join "," $l -}}
{{- end -}}


{{/*
controller.quorum.voters — brokers 표의 앞 controllers 개: "<id>@<ip>:<controllerPort>,…".
정적 쿼럼이라 전 브로커에 같은 값이 들어간다. kafka-configmap.yaml(server.properties.tpl)이 쓴다.
*/}}
{{- define "kafka.quorumVoters" -}}
{{- $port := int .Values.global.kafka.ports.controller -}}
{{- $n := int .Values.global.kafka.controllers -}}
{{- $l := list -}}
{{- range $i, $node := .Values.global.kafka.brokers }}{{ if lt $i $n }}{{ $l = append $l (printf "%d@%s:%d" $i $node.ip $port) }}{{ end }}{{ end -}}
{{- join "," $l -}}
{{- end -}}
