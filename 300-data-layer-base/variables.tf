# ===============================================
# [클러스터 접속 / 공통]
# ===============================================

variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "데이터 레이어 네임스페이스 (이 스택이 소유·생성한다)"
  type        = string
  default     = "data-layer"
}

# ===============================================
# [Kafka 브로커 접속 — 클러스터 외부]
#   → ADR 0 에 따라 브로커는 K8s 가 아니라 노드 로컬(systemd)에 있다(Ansible kafka 롤).
#   → 저장소 전체에서 브로커 주소의 유일한 정의 지점이다 — 301 은 복사하지 않고 ConfigMap 을 읽는다.
# ===============================================

# 환경(노드 IP)마다 달라지는 값이라 default 없음 → tfvars 강제
variable "kafka_bootstrap_servers" {
  description = "로컬 Kafka 브로커 bootstrap 목록(쉼표 구분 host:port) — Ansible host.yml kafka 그룹과 일치해야 한다"
  type        = string
}

# ===============================================
# [데이터 스토어 접속 — 클러스터 외부]
#   → MinIO·PostgreSQL·Neo4j 도 브로커(ADR 0)와 같은 이유로 노드 로컬 설치다(Ansible — 추후 작성).
#   → 이 스택은 서버를 만들지 않고 공용 ConfigMap 의 엔드포인트·DSN·URI 만 조립한다.
# ===============================================

# 셋 다 환경(노드 주소)마다 달라지는 값이라 default 없음 → tfvars 강제
variable "minio_endpoint" {
  description = "로컬 MinIO S3 엔드포인트(http://host:port) — 로컬 설치 위치와 일치해야 한다"
  type        = string
}

variable "postgres_host" {
  description = "로컬 PostgreSQL 호스트 — 포트는 postgres_port 로 따로 받는다"
  type        = string
}

# MinIO·Neo4j 는 포트가 엔드포인트 문자열 안에 있어 변수가 따로 없다. PostgreSQL 만
# host 와 port 를 나눠 받는 이유는 libpq keyword DSN(host=... port=...)이 둘을 별도
# 필드로 요구하기 때문. 표준 포트라 여기는 default 를 둔다.
variable "postgres_port" {
  description = "로컬 PostgreSQL 포트 — DSN 3종과 Iceberg 카탈로그 URI 가 공유한다"
  type        = number
  default     = 5432
}

variable "neo4j_bolt_uri" {
  description = "로컬 Neo4j Bolt URI(bolt://host:port) — PLATFORM_NEO4J_URI 로 그대로 나간다"
  type        = string
}

# ===============================================
# [다른 스택이 소유한 값의 미러]
#   → 공용 ConfigMap 의 *_URL 은 여기서 조립해야 하는데 state 가 독립이라 소유 스택의 변수를 못 읽는다.
#   → ⚠ 여기 값을 바꿔도 Service·Ingress·containerPort 는 안 따라온다 — 원 스택과 같은 커밋에서 고칠 것.
#   → 이 스택이 실제로 조립에 쓰는 값만 미러한다(kafka-exporter 9097 같은 건 두지 말 것).
#   → 브라우저용 주소에 포트 미러가 없는 것은 의도다 — 인그레스가 VIP 의 80 하나로 받으므로
#     URL 조립에 필요한 것은 호스트명뿐이다.
# ===============================================

variable "kafka_ui_host" {
  description = "kafka-ui 접속 호스트명 (301-kafka-tools 소유 — 바로가기 URL 조립용 미러 선언)"
  type        = string
  default     = "data-layer-kafka-ui"
}

# 아래 둘은 브라우저용이 아니라 클러스터 내부(Service DNS) 주소 조립용이다 —
# SCHEMA_REGISTRY_URL · KAFKA_CONNECT_URL 이 이 값을 쓴다.
variable "schema_registry_port" {
  description = "schema-registry ClusterIP 포트 (301-kafka-tools 의 schema_registry_port 소유 — SCHEMA_REGISTRY_URL 조립용 미러 선언)"
  type        = number
  default     = 9096
}

variable "kafka_connect_port" {
  description = "cdc-connect REST 포트 (306-cdc 의 connect_rest_port 소유 — KAFKA_CONNECT_URL 조립용 미러 선언)"
  type        = number
  default     = 8083
}

# ⚠ 304-airflow 의 AIRFLOW__API__BASE_URL 도 같은 이름으로 조립된다 — 여기만 바꾸면
#   화면의 바로가기와 Airflow 의 로그인 리다이렉트가 서로 다른 곳을 가리킨다.
variable "airflow_host" {
  description = "Airflow 접속 호스트명 (304-airflow 소유 — 바로가기 URL 조립용 미러 선언)"
  type        = string
  default     = "data-layer-airflow"
}

# GRAFANA_URL 뿐 아니라 GF_SERVER_ROOT_URL(Grafana 자기 주소)과 305-api 의 hostAliases 도
# 이 이름을 쓴다 — 셋이 같아야 iframe 임베드와 서버사이드 목록 조회가 함께 동작한다.
variable "grafana_host" {
  description = "Grafana 접속 호스트명 (302-monitoring 소유 — 바로가기/임베드 URL 조립용 미러 선언)"
  type        = string
  default     = "data-layer-grafana"
}

# ===============================================
# [공용 ConfigMap 중 환경 의존 값]
# ===============================================

variable "collector_db_name" {
  description = "플랫폼/수집 메타 DB 이름 (PG DSN 3종이 공유)"
  type        = string
  default     = "data_layer"
}

variable "collector_db_schema" {
  description = "수집 메타 테이블 스키마"
  type        = string
  default     = "data_pipeline"
}

variable "iceberg_catalog_db_name" {
  description = "pyiceberg SqlCatalog 메타데이터 DB 이름"
  type        = string
  default     = "iceberg_catalog"
}

variable "graph_label_prefix" {
  description = "CDM 그래프 라벨 접두어 — 검증 단계는 Test(기존 그래프와 분리), 실서비스는 빈 값"
  type        = string
  default     = "Test"
}

# ===============================================
# [시크릿 — Secret data-layer-secrets]
#   → 전부 default 없음 + sensitive → secrets.auto.tfvars 로만 주입한다.
#   → terraform.tfvars 는 커밋되므로 여기 값을 적지 말 것.
# ===============================================

variable "minio_root_user" {
  description = "MinIO ROOT 계정 (그대로 S3 access key 로도 쓰인다)"
  type        = string
  sensitive   = true
}

variable "minio_root_password" {
  description = "MinIO ROOT 비밀번호 (그대로 S3 secret key 로도 쓰인다)"
  type        = string
  sensitive   = true
}

variable "postgres_user" {
  description = "PostgreSQL 슈퍼유저 — PG DSN 3종과 Iceberg 카탈로그 URI 조립에 쓰인다"
  type        = string
  sensitive   = true
}

variable "postgres_password" {
  description = "PostgreSQL 비밀번호"
  type        = string
  sensitive   = true
}

variable "collector_crypto_key" {
  description = "collect_job.config 비밀번호 암호화 키(Fernet) — Airflow Variable 과 반드시 동일"
  type        = string
  sensitive   = true
}

variable "data_layer_api_key" {
  description = "data-layer-api /api/* 인증용 X-API-Key (재발급: openssl rand -hex 32)"
  type        = string
  sensitive   = true
}

variable "platform_neo4j_user" {
  description = "Neo4j 계정 (로컬 서버의 NEO4J_AUTH 와 클라이언트가 공유)"
  type        = string
  sensitive   = true
}

variable "platform_neo4j_password" {
  description = "Neo4j 비밀번호"
  type        = string
  sensitive   = true
}

variable "grafana_admin_user" {
  description = "Grafana 초기 관리자 계정 (GF_SECURITY_ADMIN_USER)"
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Grafana 초기 관리자 비밀번호 (GF_SECURITY_ADMIN_PASSWORD)"
  type        = string
  sensitive   = true
}
