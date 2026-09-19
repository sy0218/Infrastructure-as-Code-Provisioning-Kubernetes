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
Kafka Bootstrap 주소 (PLAINTEXT 스킴)
kafkaBootstrap 의 각 항목에 PLAINTEXT:// 를 붙인다 — schema-registry 가 스킴 있는 목록을 요구한다.
예: PLAINTEXT://192.168.56.38:9092,PLAINTEXT://192.168.56.39:9092,...
*/}}
{{- define "datalayer.kafkaBootstrapPlaintext" -}}
{{- $l := list -}}
{{- range splitList "," (include "datalayer.kafkaBootstrap" .) }}
{{- $l = append $l (printf "PLAINTEXT://%s" .) -}}
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
Iceberg Catalog 용 PostgreSQL SQLAlchemy URI
비밀번호는 URL 인코딩한다 — 특수문자가 URI 구분자로 해석되는 것을 막는다.
*/}}
{{- define "datalayer.icebergCatalogUri" -}}
{{- printf "postgresql+psycopg2://%s:%s@%s:%d/%s"
      .Values.global.secrets.postgresUser
      (urlquery .Values.global.secrets.postgresPassword)
      (include "datalayer.postgresHost" .)
      (int .Values.global.postgres.port)
      .Values.global.postgres.databases.icebergCatalog -}}
{{- end -}}
