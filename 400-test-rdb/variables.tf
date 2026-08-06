# ===============================================
# [클러스터 접속 / 공통]
#   → 네임스페이스는 300-data-layer-base 소유 — 여기서는 이름으로 참조만 한다.
#   → 환경마다 달라지는 값(harbor_registry·image_tag)은 default 를 주지 않아 tfvars 를 강제한다.
# ===============================================

variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "데이터 레이어 네임스페이스 (300-data-layer-base 소유)"
  type        = string
  default     = "data-layer"
}

variable "harbor_registry" {
  description = "Harbor 레지스트리 주소(스킴 없음)"
  type        = string
}

variable "image_tag" {
  description = "배포할 이미지 태그(불변 태그)"
  type        = string
}

# ===============================================
# [스토리지]
#   → 넷 다 '테스트 픽스처'다. 데이터는 cdc_seed_loader DAG 가 매일 01 시에 다시 채우므로
#     노드와 함께 사라져도 하루면 복구된다 — 그 이득에 Longhorn 3중 복제(오라클만 ~18G)를
#     쓸 이유가 없어 local-path 를 기본으로 둔다(저장소 규약의 명시적 예외).
#   ⚠ longhorn 으로 바꾸면 새 볼륨이 root 소유 0755 로 온다 — 매니페스트의 fsGroup 이 그때 의미를 갖는다.
# ===============================================

variable "test_rdb_storage_class" {
  description = "소스 RDB 4종 PVC 의 StorageClass"
  type        = string
  default     = "local-path"
}

# ===============================================
# [Oracle — CDC 소스 (LogMiner)]
#   → Debezium 이 redo 로그를 LogMiner 로 읽는다. ARCHIVELOG + FORCE LOGGING + 보충로깅이
#     전부 갖춰져야 커넥터가 기동 직후 죽지 않는다 — 앞의 둘은 이미지 env 가, 보충로깅과
#     c##dbzuser·LOGMINER_TBS 는 initdb 스크립트가 만든다.
#   → 커넥터는 CDB 루트(FREE)로 붙어 PDB(FREEPDB1)로 컨테이너를 전환한다. 그래서 계정이
#     c## 접두의 공통유저여야 한다 — 이름을 바꾸면 커넥터 JSON 의 database.user 도 같이 가야 한다.
# ===============================================

variable "oracle_port" {
  description = "Oracle 리스너 포트 — 컨테이너/ClusterIP 공통"
  type        = number
  default     = 1521
}

variable "oracle_cdb_name" {
  description = "CDB 서비스명 (커넥터 JSON 의 database.dbname 과 같아야 한다)"
  type        = string
  default     = "FREE"
}

variable "oracle_pdb_name" {
  description = "실제 데이터가 있는 PDB 이름 (커넥터 JSON 의 database.pdb.name 과 같아야 한다)"
  type        = string
  default     = "FREEPDB1"
}

# 이미지의 APP_USER 로 만들어지는 PDB 로컬 유저이자 스키마명이다.
# Oracle 은 따옴표 없는 식별자를 대문자로 저장하므로 실제 스키마는 CDC 다 —
# 커넥터 JSON 의 table.include.list(CDC.CDC_TEST_QM_CONTROL_LOOP)가 그 대문자를 쓴다.
variable "oracle_app_user" {
  description = "업무 스키마 겸 계정 (이미지 APP_USER)"
  type        = string
  default     = "cdc"
}

variable "oracle_dbz_user" {
  description = "Debezium LogMiner 접속용 공통유저 — c## 접두가 필수다(CDB 루트 접속 후 컨테이너 전환)"
  type        = string
  default     = "c##dbzuser"
}

# Free 에디션은 SGA+PGA 합계가 2GB 로 제한된다. 아래 둘은 그 상한 안에서 나눈 값이며,
# 랩 노드가 2.8Gi 뿐이라 파드가 Pending 이면 가장 먼저 낮출 값이다(1024M/256M 까지 확인됨).
variable "oracle_sga_target" {
  description = "Oracle SGA 크기 (initdb 에서 SCOPE=SPFILE 로 고정)"
  type        = string
  default     = "1536M"
}

variable "oracle_pga_aggregate_target" {
  description = "Oracle PGA 총량 (initdb 에서 SCOPE=SPFILE 로 고정)"
  type        = string
  default     = "512M"
}

variable "oracle_storage_size" {
  description = "Oracle 데이터파일 PVC 크기 — 실사용 6.1G(oradata + FRA 아카이브)"
  type        = string
  default     = "20Gi"
}

variable "oracle_memory_request" {
  description = "Oracle 파드 메모리 요청 — SGA+PGA 는 지연 할당이라 실사용(약 600Mi)에 맞춘다"
  type        = string
  default     = "1Gi"
}

variable "oracle_cpu_request" {
  description = "Oracle 파드 CPU 요청"
  type        = string
  default     = "250m"
}

# ===============================================
# [SQL Server — CDC 소스 (네이티브 CDC)]
#   → 로그를 직접 읽지 않는다. SQL Agent 잡이 변경분을 cdc.* 테이블에 적재하고 Debezium 이
#     그것을 폴링한다 → MSSQL_AGENT_ENABLED 가 꺼지면 변경이 아예 캡처되지 않는다.
#   → 넷 중 유일하게 이미지에 초기화 훅이 없다 → 부트스트랩이 별도 Job 이다(mssql.tf 참조).
# ===============================================

variable "mssql_port" {
  description = "SQL Server 포트 — 컨테이너/ClusterIP 공통"
  type        = number
  default     = 1433
}

variable "mssql_database" {
  description = "CDC 대상 데이터베이스 (커넥터 JSON 의 database.names 와 같아야 한다)"
  type        = string
  default     = "cdc"
}

variable "mssql_edition" {
  description = "SQL Server 에디션 (MSSQL_PID) — Developer 는 무료이면서 기능 제한이 없다"
  type        = string
  default     = "Developer"
}

# docker 원본에는 없던 항목이다. 상한이 없으면 SQL Server 가 노드 메모리 전체를 버퍼풀
# 후보로 잡아 2.8Gi 노드에서 다른 파드를 밀어낸다 — 랩에 맞춰 명시적으로 묶는다.
variable "mssql_memory_limit_mb" {
  description = "SQL Server max server memory (MB)"
  type        = number
  default     = 1024
}

variable "mssql_storage_size" {
  description = "SQL Server 데이터 PVC 크기 — 실사용 190M(시스템 DB 포함)"
  type        = string
  default     = "8Gi"
}

variable "mssql_memory_request" {
  description = "SQL Server 파드 메모리 요청"
  type        = string
  default     = "1Gi"
}

variable "mssql_cpu_request" {
  description = "SQL Server 파드 CPU 요청"
  type        = string
  default     = "250m"
}

# ===============================================
# [PostgreSQL — CDC 소스 (논리복제 / pgoutput)]
#   → 넷 중 유일하게 DDL 이력 토픽이 필요 없고, 대신 publication 과 복제 슬롯이 상태다.
#   ⚠ 슬롯은 커넥터를 지워도 DB 에 남아 WAL 을 붙잡는다 — 정리할 때 pg_drop_replication_slot 까지 할 것.
# ===============================================

variable "postgres_port" {
  description = "PostgreSQL 포트 — 컨테이너/ClusterIP 공통"
  type        = number
  default     = 5432
}

variable "postgres_database" {
  description = "CDC 대상 데이터베이스 (커넥터 JSON 의 database.dbname 과 같아야 한다)"
  type        = string
  default     = "cdc"
}

variable "postgres_user" {
  description = "CDC 접속 계정 — 이미지가 슈퍼유저로 만들어 REPLICATION 권한이 따라온다"
  type        = string
  default     = "cdc"
}

variable "postgres_publication" {
  description = "논리복제 publication 이름 (커넥터 JSON 의 publication.name 과 같아야 한다)"
  type        = string
  default     = "cdc_test_pub"
}

variable "postgres_storage_size" {
  description = "PostgreSQL 데이터 PVC 크기 — 실사용 47M"
  type        = string
  default     = "4Gi"
}

variable "postgres_memory_request" {
  description = "PostgreSQL 파드 메모리 요청"
  type        = string
  default     = "256Mi"
}

variable "postgres_cpu_request" {
  description = "PostgreSQL 파드 CPU 요청"
  type        = string
  default     = "100m"
}

# ===============================================
# [MySQL — CDC 소스 (binlog)]
#   → 복제 클라이언트로 붙어 binlog 를 읽는다. ROW + FULL 이미지가 아니면 before 가 비고,
#     server-id 가 커넥터(5001)와 겹치면 서로 연결을 끊는다.
# ===============================================

variable "mysql_port" {
  description = "MySQL 포트 — 컨테이너/ClusterIP 공통"
  type        = number
  default     = 3306
}

variable "mysql_database" {
  description = "CDC 대상 데이터베이스 (커넥터 JSON 의 database.include.list 와 같아야 한다)"
  type        = string
  default     = "cdc"
}

variable "mysql_user" {
  description = "CDC 접속 계정 — 복제 권한은 initdb 스크립트가 따로 준다"
  type        = string
  default     = "cdc"
}

# 커넥터의 database.server.id(5001)와 절대 겹치면 안 된다 — 겹치면 서로 binlog 연결을 끊는다.
variable "mysql_server_id" {
  description = "MySQL 복제 식별자 (소스 자신의 server-id)"
  type        = number
  default     = 1
}

variable "mysql_binlog_expire_seconds" {
  description = "binlog 보존 기간(초) — 커넥터가 이보다 오래 멈추면 위치를 잃는다"
  type        = number
  default     = 604800
}

variable "mysql_storage_size" {
  description = "MySQL 데이터 PVC 크기 — 실사용 199M(binlog 포함)"
  type        = string
  default     = "4Gi"
}

variable "mysql_memory_request" {
  description = "MySQL 파드 메모리 요청"
  type        = string
  default     = "384Mi"
}

variable "mysql_cpu_request" {
  description = "MySQL 파드 CPU 요청"
  type        = string
  default     = "100m"
}

# ===============================================
# [시크릿 — Secret test-rdb-secrets]
#   → default 없음 + sensitive → secrets.auto.tfvars 로만 주입한다.
#   → 넷이 비밀번호 하나를 공유하는 것은 의도다: 커넥터 JSON 4종의 자리표시자가
#     ${CDC_SOURCE_DB_PASSWORD} 하나뿐이라, 계정마다 다른 값을 쓰면 등록 화면에서 구분이 안 된다.
# ===============================================

variable "cdc_source_db_password" {
  description = "CDC 소스 RDB 4종의 공용 비밀번호 (data_pipeline/.env 의 CDC_SOURCE_DB_PASSWORD 와 같아야 한다)"
  type        = string
  sensitive   = true
}
