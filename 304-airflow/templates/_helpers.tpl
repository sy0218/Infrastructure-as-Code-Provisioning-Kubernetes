{{/*
===============================================
[304-airflow 공통 Helper]

값 '변환'이 끼는 조합만 둔다 — 단순 조합(이미지 주소)·정적 블록(라벨·envFrom)은
각 템플릿에 직접 명시한다.
===============================================
*/}}


{{/*
CNPG Primary(-rw Service)의 PostgreSQL FQDN 생성

DSN 조립과 NOTES 가 함께 쓴다 — 주소를 두 곳에 따로 적지 않기 위한 헬퍼다.
*/}}
{{- define "airflow.postgresHost" -}}
{{- printf "%s-rw.%s.svc.cluster.local" .Values.global.postgres.clusterName .Values.global.namespace -}}
{{- end -}}


{{/*
PostgreSQL 접속용 SQLAlchemy DSN 생성

비밀번호는 URL 인코딩하여 특수문자 문제를 방지한다.
*/}}
{{- define "airflow.sqlAlchemyConn" -}}
{{- printf "postgresql+psycopg2://%s:%s@%s:%d/%s"
      .Values.global.secrets.postgresUser
      (urlquery .Values.global.secrets.postgresPassword | replace "+" "%20")
      (include "airflow.postgresHost" .)
      (int .Values.global.postgres.port)
      .Values.global.postgres.databases.airflow -}}
{{- end -}}


{{/*
Kafka bootstrap 주소 조립 — global.kafka.brokers 표 × ports.client

300 의 datalayer.kafkaBootstrap 과 같은 원본·같은 방식이다(복사본이 아니라 파생값).
Connection collector_kafka 의 host 가 되며, 브로커는 hostNetwork 라 Service 가 없다.
*/}}
{{- define "airflow.kafkaBootstrap" -}}
{{- $port := int .Values.global.kafka.ports.client -}}
{{- $l := list -}}
{{- range .Values.global.kafka.brokers }}
{{- $l = append $l (printf "%s:%d" .ip $port) -}}
{{- end -}}
{{- join "," $l -}}
{{- end -}}
