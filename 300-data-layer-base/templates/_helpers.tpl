{{/*
공통 접속 정보 헬퍼
global의 원본값으로 실제 접속 주소를 생성한다.
주소를 values에 중복 정의하지 않아 설정 불일치를 방지한다.
*/}}

{{/*
Cluster DNS 접미사
예: data-layer.svc.cluster.local
*/}}
{{- define "datalayer.svcSuffix" -}}
{{- printf "%s.svc.cluster.local" .Values.global.namespace -}}
{{- end -}}


{{/*
Kafka Bootstrap 주소
Broker IP와 Client Port로 bootstrap 주소를 생성한다.
예: 192.168.56.38:9092,192.168.56.39:9092,...
*/}}
{{- define "datalayer.kafkaBootstrap" -}}
{{- $port := int .Values.global.kafka.ports.client -}}
{{- $l := list -}}
{{- range .Values.global.kafka.brokers }}
{{- $l = append $l (printf "%s:%d" .ip $port) -}}
{{- end -}}
{{- join "," $l -}}
{{- end -}}


{{/*
PostgreSQL 접속 호스트
CNPG의 -rw Service를 사용해 현재 Primary에 연결한다.
*/}}
{{- define "datalayer.postgresHost" -}}
{{- printf "%s-rw.%s" .Values.global.postgres.clusterName (include "datalayer.svcSuffix" .) -}}
{{- end -}}


{{/*
Collector DB용 PostgreSQL DSN
공통 PostgreSQL 접속 정보를 libpq 형식으로 조립한다.
*/}}
{{- define "datalayer.postgresDsn" -}}
{{- printf "host=%s port=%d dbname=%s user=%s password=%s"
      (include "datalayer.postgresHost" .)
      (int .Values.global.postgres.port)
      .Values.global.postgres.databases.collector
      .Values.global.secrets.postgresUser
      .Values.global.secrets.postgresPassword -}}
{{- end -}}
{{/*
controller.quorum.voters — brokers 표의 앞 controllers 개: "<id>@<ip>:<controllerPort>,…".
정적 쿼럼이라 전 브로커에 같은 값이 들어간다. kafka-config(server.properties)가 쓴다.
*/}}
{{- define "datalayer.kafkaQuorumVoters" -}}
{{- $port := int .Values.global.kafka.ports.controller -}}
{{- $n := int .Values.global.kafka.controllers -}}
{{- $l := list -}}
{{- range $i, $node := .Values.global.kafka.brokers }}{{ if lt $i $n }}{{ $l = append $l (printf "%d@%s:%d" $i $node.ip $port) }}{{ end }}{{ end -}}
{{- join "," $l -}}
{{- end -}}
