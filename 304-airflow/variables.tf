# ===============================================
# [클러스터 접속 / 공통]
# ===============================================

variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "데이터 레이어 네임스페이스 (300-data-layer-base 가 소유 — 여기서는 참조만)"
  type        = string
  default     = "data-layer"
}

# 아래 둘은 default 없음 → 환경/배포마다 달라지는 값이라 tfvars 강제
variable "harbor_registry" {
  description = "Harbor 레지스트리 주소(스킴 없음)"
  type        = string
}

variable "image_tag" {
  description = "배포할 이미지 태그(불변 태그)"
  type        = string
}

# ===============================================
# [데이터 스토어 접속]
#   → PostgreSQL(메타DB)은 303-postgres 의 CNPG 클러스터다 — 접속은 Service DNS(-rw).
#     MinIO(로그/설정)는 여전히 노드 로컬 설치(Ansible)라 노드 주소로 붙는다.
#   → 300-data-layer-base(values.yaml)의 같은 의미 값과 일치해야 한다.
# ===============================================

# 호스트·엔드포인트는 환경마다 달라지는 값이라 default 없음 → tfvars 강제
variable "postgres_host" {
  description = "PostgreSQL 호스트 — CNPG rw Service FQDN (300-data-layer-base 의 global.postgresHost 와 같은 값)"
  type        = string
}

# 표준 포트라 여기는 default 를 준다 — 바꿀 때 300 쪽 postgresPort 와 함께 고칠 것
variable "postgres_port" {
  description = "PostgreSQL 포트 (300-data-layer-base 의 postgresPort 와 같은 값)"
  type        = number
  default     = 5432
}

variable "minio_endpoint" {
  description = "로컬 MinIO S3 엔드포인트 (300-data-layer-base 의 minioEndpoint 와 같은 값)"
  type        = string
}

# ===============================================
# [DAG 파싱]
#   → 코드(DAG·커스텀 패키지)는 airflow 이미지 안(/opt/airflow/repo)에 있다.
#     DAG 반영 = 이미지 재빌드 → image_tag 변경 → 롤아웃.
# ===============================================

variable "dag_bundle_refresh_interval" {
  description = "dag-processor 가 DAG 폴더를 다시 훑는 주기(초) — 새 파일이 목록에 나타나기까지의 지연"
  type        = number
  default     = 30
}

# ===============================================
# [실행 계정]
#   → apache/airflow 이미지는 UID 50000 으로 pip --user 설치를 해 두고 AIRFLOW_HOME 이하를
#     그룹 0 쓰기 가능으로 만든다 — 다른 UID/GID 로 뜨면 커스텀 패키지를 못 읽거나
#     설정/캐시 파일을 못 쓴다.
# ===============================================

variable "airflow_run_as_user" {
  description = "Airflow 컨테이너 실행 UID"
  type        = number
  default     = 50000
}

variable "airflow_fs_group" {
  description = "컨테이너 runAsGroup 겸 파드 fsGroup (이미지가 그룹 0 쓰기를 전제한다)"
  type        = number
  default     = 0
}

# ===============================================
# [컴포넌트 복제 수]
#   → 4개 전부 stateless(로그 S3 · DAG 이미지)라 숫자만 늘리면 되지만,
#     LocalExecutor 에서는 scheduler 가 곧 워커라 1 로 시작한다.
# ===============================================

variable "apiserver_replicas" {
  description = "airflow api-server 복제 수 (늘려도 안전한 유일한 컴포넌트)"
  type        = number
  default     = 1
}

variable "scheduler_replicas" {
  description = "airflow scheduler 복제 수 (LocalExecutor 에서는 태스크 실행 주체이기도 하다)"
  type        = number
  default     = 1
}

variable "dag_processor_replicas" {
  description = "airflow dag-processor 복제 수"
  type        = number
  default     = 1
}

variable "triggerer_replicas" {
  description = "airflow triggerer 복제 수 (deferrable 오퍼레이터용)"
  type        = number
  default     = 1
}

# ===============================================
# [Airflow 설정 — 비밀 아닌 값]
# ===============================================

variable "airflow_executor" {
  description = "AIRFLOW__CORE__EXECUTOR — KubernetesExecutor 면 태스크마다 파드가 뜬다(executor.tf 의 원형)"
  type        = string
  default     = "KubernetesExecutor"
}

# ⚠ 아래 둘은 성능 손잡이가 아니라 안전 장치다. 태스크 파드 requests(384Mi)와 곱한 값이
#   클러스터 여유를 넘으면 태스크가 실행되는 대신 Pending 으로 쌓인다.
variable "airflow_parallelism" {
  description = "AIRFLOW__CORE__PARALLELISM — 클러스터 전체 동시 태스크 상한"
  type        = number
  default     = 10
}

variable "airflow_max_active_tasks_per_dag" {
  description = "AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG — DAG 하나가 독점하지 못하게 하는 상한"
  type        = number
  default     = 4
}

variable "airflow_db_name" {
  description = "Airflow 메타DB 이름 — 로컬 PostgreSQL 에 미리 만들어져 있어야 한다"
  type        = string
  default     = "airflow"
}

# 버킷 생성은 클러스터 밖(로컬 MinIO 설치) 책임이다 — 미리 만들어 둘 것.
# 버킷이 없으면 태스크는 정상 종료해도 로그가 사라진다(업로드 실패는 태스크를 죽이지 않는다).
variable "airflow_logs_bucket" {
  description = "태스크 로그를 올릴 S3(MinIO) 버킷"
  type        = string
  default     = "airflow-logs"
}

variable "objstore_bucket" {
  description = "도메인 설정(config/*.yaml) 버킷 — 매퍼/컨슈머와 같은 값이어야 한다"
  type        = string
  default     = "config"
}

variable "airflow_log_level" {
  description = "AIRFLOW__LOGGING__LOGGING_LEVEL — 태스크 코드의 basicConfig 는 무시되므로 이 값이 실효 레벨이다"
  type        = string
  default     = "INFO"
}

# ⚠ airflow.cfg 와 달리 env 값은 configparser 보간을 타지 않는다 → % 를 겹쳐 쓰면 안 된다
variable "airflow_log_format" {
  description = "AIRFLOW__LOGGING__LOG_FORMAT"
  type        = string
  default     = "%(asctime)s %(levelname)s %(name)s %(message)s"
}

variable "timezone" {
  description = "TZ · CDM_TZ · AIRFLOW__CORE__DEFAULT_TIMEZONE 의 단일 출처"
  type        = string
  default     = "Asia/Seoul"
}

# MinIO 는 리전 개념을 쓰지 않지만 boto3 는 리전이 없으면 서명을 만들지 못한다 → 형식상 필수
variable "aws_region" {
  description = "MinIO 커넥션의 region_name"
  type        = string
  default     = "us-east-1"
}

# ===============================================
# [ClusterIP 포트 — 이 스택이 소유자]
#   → api-server 포트 하나가 containerPort · Service port · EXECUTION_API_SERVER_URL ·
#     output 네 곳에 나온다. 변수 하나에서 주입해 어긋날 방법 자체를 없앤다.
#   → 환경마다 달라질 값이 아니라 default 를 준다.
# ===============================================

variable "airflow_apiserver_port" {
  description = "api-server 컨테이너/ClusterIP 포트 — Ingress 백엔드가 가리키는 포트이기도 하다"
  type        = number
  default     = 8080
}

# ===============================================
# [외부 접속 — Ingress 호스트명]
#   → 서비스 전용 호스트명(data-layer-airflow)이 102-ingress 의 VIP 로 풀린다
#     (Ansible etc_hosts) → 노드 한 대가 죽어도 이름이 그대로 유효하다.
#   → 하이픈 구분자(밑줄 금지, RFC 1123)와 `.local` 미사용(mDNS 예약)은 저장소 공통 규칙.
#   → 이름 전체 표의 소유자는 README 다.
# ===============================================

# ⚠ 이 이름 하나가 세 곳에 동시에 들어간다 — Ingress 의 host, AIRFLOW__API__BASE_URL,
#   300-data-layer-base 의 AIRFLOW_UI_URL. 하나라도 어긋나면 로그인 화면까지는 뜨는데
#   인증 직후 리다이렉트가 엉뚱한 곳으로 튄다.
variable "airflow_host" {
  description = "Airflow UI 접속 호스트명 — Ingress 규칙의 host (Ansible etc_hosts 가 VIP 로 푼다)"
  type        = string
  default     = "data-layer-airflow"
}

# ===============================================
# [시크릿]
#   → 전부 default 없음 + sensitive → secrets.auto.tfvars 로만 주입한다.
#   → terraform.tfvars 는 커밋되므로 여기에 값을 적지 말 것.
# ===============================================

variable "postgres_user" {
  description = "Airflow 메타DB 접속 계정 (300-data-layer-base 의 postgres_user 와 같은 값)"
  type        = string
  sensitive   = true
}

variable "postgres_password" {
  description = "Airflow 메타DB 비밀번호"
  type        = string
  sensitive   = true
}

variable "minio_access_key" {
  description = "MinIO S3 access key — 설정 오브젝트 읽기 + 원격 로그 쓰기에 함께 쓰인다"
  type        = string
  sensitive   = true
}

variable "minio_secret_key" {
  description = "MinIO S3 secret key"
  type        = string
  sensitive   = true
}

# 미설정 시 파드마다 랜덤 생성 → "Invalid auth token: Signature verification failed"
variable "airflow_api_secret_key" {
  description = "AIRFLOW__API__SECRET_KEY — 4개 컴포넌트가 같은 값을 공유해야 한다"
  type        = string
  sensitive   = true
}

variable "airflow_jwt_secret" {
  description = "AIRFLOW__API_AUTH__JWT_SECRET — 워커가 Execution API 를 부를 때 쓰는 JWT 서명 키"
  type        = string
  sensitive   = true
}

# ⚠ 값을 바꾸면 메타DB 에 이미 저장된 커넥션/변수를 전부 못 읽는다(복호화 실패)
variable "airflow_fernet_key" {
  description = "AIRFLOW__CORE__FERNET_KEY — Connection/Variable 값 암호화 키"
  type        = string
  sensitive   = true
}

variable "airflow_admin_username" {
  description = "초기 관리자 계정 (init Job 이 생성)"
  type        = string
  sensitive   = true
}

variable "airflow_admin_password" {
  description = "초기 관리자 비밀번호"
  type        = string
  sensitive   = true
}

variable "airflow_admin_firstname" {
  description = "초기 관리자 이름(FAB 스키마 필수 필드)"
  type        = string
  default     = "Admin"
}

variable "airflow_admin_lastname" {
  description = "초기 관리자 성(FAB 스키마 필수 필드)"
  type        = string
  default     = "User"
}

variable "airflow_admin_email" {
  description = "초기 관리자 이메일(FAB 스키마 필수 필드 — 알림 발송에는 쓰이지 않는다)"
  type        = string
  default     = "admin@example.com"
}
