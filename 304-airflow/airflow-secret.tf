# ===============================================
# [Airflow 설정 Secret — airflow-env]
#   → AIRFLOW__<섹션>__<키> 는 Airflow 만의 계약이라 공용 ConfigMap 에 섞지 않는다
#     (섞으면 전 워크로드가 쓰지도 않는 40여 개 키를 달고 뜬다).
#   → SQL_ALCHEMY_CONN·FERNET_KEY·JWT_SECRET 이 섞여 통째로 Secret 이며, state 에
#     평문이 남지 않도록 typed 리소스를 쓴다.
#   → 5개 워크로드(init Job + 코어 4개)가 envFrom 으로 이 하나를 공유한다.
# ===============================================

locals {
  # sqlalchemy URL 이라 비밀번호의 특수문자는 URL 인코딩 필수('!' → %21)
  airflow_sql_alchemy_conn = "postgresql+psycopg2://${var.postgres_user}:${urlencode(var.postgres_password)}@${var.postgres_host}:${var.postgres_port}/${var.airflow_db_name}"

  # 아래 EXECUTION_API_SERVER_URL 과 outputs.tf 가 이 한 값을 공유한다 —
  # 양쪽에 리터럴로 두면 한쪽만 고쳐도 plan 이 통과해 output 이 조용히 거짓말한다.
  execution_api_server_url = "http://airflow-apiserver:${var.airflow_apiserver_port}/execution/"

  # 커넥션을 메타DB 가 아니라 env(AIRFLOW_CONN_<CONN_ID>)로 준다 — 원격 로깅은 첫 태스크
  # 이전에 이미 동작해야 하는데, init Job 이 커넥션을 심는 순서를 Terraform 이 보장하지 못한다.
  # endpoint_url 이 두 자리인 이유: amazon 프로바이더가 읽는 위치가 extra.endpoint_url →
  # extra.service_config.s3.endpoint_url 로 옮겨갔다. 둘 다 적어야 로그가 AWS 로 새지 않는다.
  airflow_conn_minio_logs = jsonencode({
    conn_type = "aws"
    extra = {
      aws_access_key_id     = var.minio_access_key
      aws_secret_access_key = var.minio_secret_key
      endpoint_url          = var.minio_endpoint
      region_name           = var.aws_region
      service_config = {
        s3 = {
          endpoint_url = var.minio_endpoint
        }
      }
    }
  })
}

resource "kubernetes_secret_v1" "airflow_env" {
  metadata {
    name      = "airflow-env"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"    = "airflow"
      "app.kubernetes.io/part-of" = "data-layer"
    }
  }

  type = "Opaque"

  data = {
    # ── 코어 ──────────────────────────────────────────────
    AIRFLOW__CORE__EXECUTOR = var.airflow_executor
    # 기본값은 SimpleAuthManager(사용자 테이블 없음) → 기존 화면/계정 체계를 쓰려면 FAB 명시
    AIRFLOW__CORE__AUTH_MANAGER                = "airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager"
    AIRFLOW__CORE__LOAD_EXAMPLES               = "false"
    AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION = "true"
    AIRFLOW__CORE__DEFAULT_TIMEZONE            = var.timezone
    AIRFLOW__CORE__FERNET_KEY                  = var.airflow_fernet_key
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN        = local.airflow_sql_alchemy_conn

    # ── 코드 위치 ─────────────────────────────────────────
    # DAG·커스텀 패키지는 이미지 안에 구워져 있다(data_layer_airflow/Dockerfile 의 COPY).
    # ⚠ PYTHONPATH 를 빼면 `from collector ...` 가 깨진다. 이전에 그게 되던 이유는
    #   AIRFLOW_HOME 이 sys.path 에 있어서가 아니라 작업 디렉토리가 /opt/airflow 였기 때문이다
    #   (import airflow 후 sys.path 에 추가되는 것은 config·plugins 둘뿐 — 실측 확인).
    AIRFLOW__CORE__DAGS_FOLDER = "/opt/airflow/repo/dags"
    PYTHONPATH                 = "/opt/airflow/repo"

    # ── API / 인증 ────────────────────────────────────────
    # ⚠ 아래 두 URL 은 이름만 비슷하고 역할이 정반대다 — 한쪽에 다른 쪽 값을 넣으면
    #   UI 나 태스크 실행 중 하나가 조용히 망가진다.
    #
    # ① 바깥 → 안. 로그인 리다이렉트와 절대 URL 의 기준이라 브라우저가 실제로 치는 주소여야 한다.
    #   내부 이름이면 브라우저가 풀지 못하고, 특정 노드 IP 를 박으면 그 노드가 죽는 순간
    #   파드는 멀쩡한데 UI 만 접속 불가가 된다 → 외부 호스트명(인그레스 Host)이어야 HA 가 성립한다.
    #   포트가 없는 것은 인그레스가 VIP 의 80 을 쓰기 때문이다 — Ingress 의 host,
    #   300-data-layer-base 의 AIRFLOW_UI_URL 과 글자 그대로 같아야 한다.
    AIRFLOW__API__BASE_URL = "http://${var.airflow_host}"

    # ② 안 → 안. LocalExecutor 워커(scheduler 파드)가 태스크 상태를 보고하는 내부 주소.
    #   ⚠ 외부 이름으로 바꾸지 말 것 — 파드 안에서 해석되지 않고, 설령 hostAliases 로
    #     풀어 줘도 파드 → VIP → 인그레스 → 파드로 우회해 인그레스 장애가 곧 태스크 정지가 된다.
    AIRFLOW__CORE__EXECUTION_API_SERVER_URL = local.execution_api_server_url

    # 4개 컴포넌트가 같은 값을 공유해야 서명 검증이 통과된다(파드마다 랜덤이면 전부 401)
    AIRFLOW__API__SECRET_KEY      = var.airflow_api_secret_key
    AIRFLOW__API_AUTH__JWT_SECRET = var.airflow_jwt_secret

    # ── KubernetesExecutor ────────────────────────────────
    # 태스크 하나당 파드 하나. scheduler 가 아래 원형(executor.tf 의 ConfigMap)으로 찍는다.
    AIRFLOW__KUBERNETES_EXECUTOR__NAMESPACE         = var.namespace
    AIRFLOW__KUBERNETES_EXECUTOR__POD_TEMPLATE_FILE = local.pod_template_path
    # 성공한 파드는 지우고 실패한 파드는 남긴다 — 남겨야 kubectl logs 로 죽은 이유를 본다
    # (원격 로깅이 있어도 기동 자체가 실패하면 S3 에 아무것도 올라가지 않는다).
    AIRFLOW__KUBERNETES_EXECUTOR__DELETE_WORKER_PODS_ON_FAILURE = "False"

    # ⚠ 랩 메모리가 유일한 제약이다. 태스크 파드 requests(384Mi) × 이 값이 동시에 필요한 양이고,
    #   넘치면 파드가 뜨는 게 아니라 Pending 으로 쌓인다.
    AIRFLOW__CORE__PARALLELISM              = tostring(var.airflow_parallelism)
    AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG = tostring(var.airflow_max_active_tasks_per_dag)

    # ── DAG 파싱 ──────────────────────────────────────────
    # 코드가 이미지에 있어 롤아웃과 함께 갱신되므로 이 주기는 예민하지 않다 —
    # 기본 300초 대신 짧게 두는 것은 파일이 몇 개뿐이라 재스캔 비용이 무시할 만해서다.
    AIRFLOW__DAG_PROCESSOR__REFRESH_INTERVAL = tostring(var.dag_bundle_refresh_interval)

    # ── 스케줄러 ──────────────────────────────────────────
    # 8974 에 /health 를 띄운다 — scheduler Deployment 의 probe 가 이 값에 의존한다.
    # 끄면 probe 가 즉시 실패해 CrashLoop 처럼 보인다(원인은 설정 한 줄).
    AIRFLOW__SCHEDULER__ENABLE_HEALTH_CHECK = "true"

    # ── 로깅 ──────────────────────────────────────────────
    AIRFLOW__LOGGING__LOGGING_LEVEL = var.airflow_log_level
    AIRFLOW__LOGGING__LOG_FORMAT    = var.airflow_log_format

    # 원격 로깅 3키 — 이 스택에 PVC 가 하나도 없는 이유. 로그를 S3 에 두면 누가 어디서
    # 실행했든 UI 가 같은 곳에서 읽어 4개 컴포넌트가 자유 스케줄된다.
    # ⚠ 실행 '중'인 태스크의 라이브 로그는 UI 에 보이지 않는다(워커 로컬 파일이라).
    #   업로드가 끝난 뒤에야 나타난다 — 그 사이엔 kubectl logs 를 쓴다.
    # ⚠ 이미지에 amazon 프로바이더가 없으면 이 3키는 에러 없이 무시되고 로그만 사라진다.
    AIRFLOW__LOGGING__REMOTE_LOGGING         = "True"
    AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER = "s3://${var.airflow_logs_bucket}"
    AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID     = "minio_logs"

    # 위 REMOTE_LOG_CONN_ID 가 가리키는 커넥션의 실체(conn_id = minio_logs)
    AIRFLOW_CONN_MINIO_LOGS = local.airflow_conn_minio_logs

    # ── CDM 설정 오브젝트 저장소 ──────────────────────────
    # utils/cdm_config.py 가 이 버킷의 config/*.yaml 을 읽는다.
    # 매퍼/컨슈머와 같은 버킷이어야 한다 — 어긋나면 조용히 다른 id_columns 를 쓴다.
    CDM_OBJSTORE_ENDPOINT   = var.minio_endpoint
    CDM_OBJSTORE_ACCESS_KEY = var.minio_access_key
    CDM_OBJSTORE_SECRET_KEY = var.minio_secret_key
    CDM_OBJSTORE_BUCKET     = var.objstore_bucket

    # ── 타임존 ────────────────────────────────────────────
    TZ     = var.timezone
    CDM_TZ = var.timezone

    # ── 초기 관리자 계정 ──────────────────────────────────
    # 읽는 것은 init Job 뿐이다(같은 Secret 이라 워커에도 들어간다).
    # 계정용 Secret 을 따로 만들면 "airflow 설정이 두 곳"이 되는 쪽이 더 나쁘다.
    AIRFLOW_ADMIN_USERNAME  = var.airflow_admin_username
    AIRFLOW_ADMIN_PASSWORD  = var.airflow_admin_password
    AIRFLOW_ADMIN_FIRSTNAME = var.airflow_admin_firstname
    AIRFLOW_ADMIN_LASTNAME  = var.airflow_admin_lastname
    AIRFLOW_ADMIN_EMAIL     = var.airflow_admin_email
  }
}
