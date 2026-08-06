# ===============================================
# [접속값 조립]
#   → tfvars 로 받은 원시 주소를 워크로드가 그대로 쓸 수 있는 URL/DSN 형태로 가공한다.
#   → 가공이 필요 없는 값(엔드포인트·호스트)은 아래 ConfigMap 에서 var 를 직접 참조한다.
# ===============================================
locals {
  # 클러스터 내부 Service DNS 접미사 — 예: schema-registry.data-layer.svc.cluster.local
  svc_suffix = "${var.namespace}.svc.cluster.local"

  # bootstrap 목록의 각 host:port 에 PLAINTEXT:// 를 붙인 schema-registry 전용 형태
  kafka_bootstrap_plaintext = join(",", [for b in split(",", var.kafka_bootstrap_servers) : "PLAINTEXT://${b}"])

  # 포트 소유자는 Service 를 만드는 각 스택이다 — variables.tf 의 [다른 스택이 소유한 값의 미러] 참조
  schema_registry_url = "http://schema-registry.${local.svc_suffix}:${var.schema_registry_port}"
  kafka_connect_url   = "http://cdc-connect.${local.svc_suffix}:${var.kafka_connect_port}"

  # libpq keyword DSN — PLATFORM/LINEAGE/TCP_SOCKET 세 키가 같은 문자열을 공유한다
  platform_pg_dsn = "host=${var.postgres_host} port=${var.postgres_port} dbname=${var.collector_db_name} user=${var.postgres_user} password=${var.postgres_password}"

  # pyiceberg SqlCatalog 용 SQLAlchemy URI — URI 형식이라 비밀번호의 특수문자가 구분자로 먹힌다(urlencode 필수)
  iceberg_catalog_uri = "postgresql+psycopg2://${var.postgres_user}:${urlencode(var.postgres_password)}@${var.postgres_host}:${var.postgres_port}/${var.iceberg_catalog_db_name}"
}

# ===============================================
# [공용 ConfigMap — data-layer-env]
#   → 301~307 이 envFrom.configMapRef 로 통째로 주입받는, 비밀이 아닌 설정값 전부.
#   → 키 이름이 곧 스택 간 계약이다 — 이름을 바꾸면 참조하는 워크로드가 조용히 빈 값을 받는다.
#   → kubectl 로 직접 고치지 말 것(다음 apply 에서 field manager 충돌).
# ===============================================
resource "kubernetes_config_map_v1" "data_layer_env" {
  metadata {
    name      = "data-layer-env"
    namespace = kubernetes_namespace_v1.data_layer.metadata[0].name
    labels = {
      "app.kubernetes.io/part-of" = "data-layer"
    }
  }

  data = {
    # Kafka / Schema Registry / Connect
    # 301 은 브로커 주소를 재계산하지 않고 KAFKA_BOOTSTRAP_PLAINTEXT 를 configMapKeyRef 로 읽는다.
    KAFKA_BOOTSTRAP           = var.kafka_bootstrap_servers
    KAFKA_BOOTSTRAP_PLAINTEXT = local.kafka_bootstrap_plaintext
    SCHEMA_REGISTRY_URL       = local.schema_registry_url
    KAFKA_CONNECT_URL         = local.kafka_connect_url
    KAFKA_UI_CLUSTER_NAME     = "kraft-cluster"

    # Kafka Topic
    CDM_TOPIC                        = "cdm-topic"
    CDM_DLQ_TOPIC                    = "dlq-cdm-topic"
    CDM_CONSUMER_RDB_DLQ_TOPIC       = "dlq-cdm-consumer-rdb"
    CDM_CONSUMER_GRAPH_DLQ_TOPIC     = "dlq-cdm-consumer-graph"
    CDM_CONSUMER_WAREHOUSE_DLQ_TOPIC = "dlq-cdm-consumer-warehouse"
    DATA_QUALITY_DLQ_TOPIC           = "dlq.raw"
    LINEAGE_TOPIC                    = "lineage-topic"
    LINEAGE_DLQ_TOPIC                = "dlq-lineage"

    # Object Storage / Iceberg
    CDM_OBJSTORE_ENDPOINT   = var.minio_endpoint
    CDM_OBJSTORE_BUCKET     = "config"
    MINIO_S3_ENDPOINT       = var.minio_endpoint
    MINIO_WAREHOUSE_BUCKET  = "warehouse"
    ICEBERG_WAREHOUSE       = "s3://warehouse/"
    ICEBERG_CATALOG_URI     = local.iceberg_catalog_uri
    ICEBERG_CATALOG_DB_NAME = var.iceberg_catalog_db_name

    # PostgreSQL
    PLATFORM_PG_DSN     = local.platform_pg_dsn
    LINEAGE_PG_DSN      = local.platform_pg_dsn
    TCP_SOCKET_PG_DSN   = local.platform_pg_dsn
    COLLECTOR_DB_HOST   = var.postgres_host
    COLLECTOR_DB_PORT   = tostring(var.postgres_port)
    COLLECTOR_DB_NAME   = var.collector_db_name
    COLLECTOR_DB_SCHEMA = var.collector_db_schema

    # Neo4j
    PLATFORM_NEO4J_URI      = var.neo4j_bolt_uri
    PLATFORM_NEO4J_DATABASE = "neo4j"
    GRAPH_LABEL_PREFIX      = var.graph_label_prefix

    # UI 바로가기 (브라우저 접근용 Ingress 주소 — 호스트명 소유자는 각 앱 스택)
    # 포트가 없는 것은 인그레스가 VIP 의 80 을 쓰기 때문이다. 이 이름들은 각 스택
    # Ingress 의 host 와 글자 그대로 같아야 한다 — 어긋나면 화면의 바로가기만 조용히 죽는다.
    KAFKA_UI_URL   = "http://${var.kafka_ui_host}"
    AIRFLOW_UI_URL = "http://${var.airflow_host}"
    GRAFANA_URL    = "http://${var.grafana_host}"

    # Data Quality
    DATA_QUALITY_MAPPER_PREFIX         = "cdm-mapper"
    DATA_QUALITY_RESTART_DRAIN_TIMEOUT = "180"

    # Mapper / Consumer / Lineage 설정
    CDM_MAPPER_LOG_LEVEL = "INFO"
    CDM_WORK_BATCH_SIZE  = "500"
    CDM_WORK_BATCH_TIME  = "60.0"
    CDM_TZ               = "Asia/Seoul"

    CDM_CONSUMER_RDB_GROUP      = "cdm-consumer-rdb"
    CDM_CONSUMER_RDB_BATCH_SIZE = "500"
    CDM_CONSUMER_RDB_BATCH_TIME = "60.0"
    CDM_CONSUMER_RDB_LOG_LEVEL  = "INFO"

    CDM_CONSUMER_GRAPH_GROUP      = "cdm-consumer-graph"
    CDM_CONSUMER_GRAPH_BATCH_SIZE = "500"
    CDM_CONSUMER_GRAPH_BATCH_TIME = "60.0"
    CDM_CONSUMER_GRAPH_LOG_LEVEL  = "INFO"

    CDM_CONSUMER_WAREHOUSE_GROUP      = "cdm-consumer-warehouse"
    CDM_CONSUMER_WAREHOUSE_BATCH_SIZE = "500"
    CDM_CONSUMER_WAREHOUSE_BATCH_TIME = "60.0"
    CDM_CONSUMER_WAREHOUSE_LOG_LEVEL  = "INFO"

    LINEAGE_GROUP      = "cdm-lineage"
    LINEAGE_LOG_LEVEL  = "INFO"
    LINEAGE_BATCH_SIZE = "500"
    LINEAGE_BATCH_TIME = "60.0"

    # TCP Socket Collector
    TCP_SOCKET_BIND             = "0.0.0.0"
    TCP_SOCKET_ORIGIN           = "socket.tcp"
    TCP_SOCKET_DLQ_TOPIC        = "dlq.raw"
    TCP_SOCKET_MAX_CONN         = "64"
    TCP_SOCKET_MAX_LINE         = "65536"
    TCP_SOCKET_IDLE_TIMEOUT     = "300"
    TCP_SOCKET_STATS_INTERVAL   = "60"
    TCP_SOCKET_REFRESH_INTERVAL = "5"
    TCP_SOCKET_LOG_LEVEL        = "INFO"
    # 컨테이너 이름이 아니라 라벨 셀렉터(app=tcp-socket-collector) 의미
    TCP_SOCKET_CONTAINER = "tcp-socket-collector"

    # Grafana Embed
    GF_SECURITY_ALLOW_EMBEDDING = "true"
    GF_AUTH_ANONYMOUS_ENABLED   = "true"
    GF_AUTH_ANONYMOUS_ORG_ROLE  = "Editor"
    # Grafana 가 리다이렉트·절대 URL 을 만들 때 쓰는 자기 주소. 호스트 기반 인그레스라
    # 없어도 대체로 동작하지만, 없으면 Grafana 는 자기 주소를 localhost:3000 으로 가정해
    # 일부 리다이렉트가 파드 안쪽을 가리킨다 → GRAFANA_URL 과 같은 값을 명시한다.
    GF_SERVER_ROOT_URL = "http://${var.grafana_host}"

    # Airflow
    AIRFLOW_UID = "50000"
  }
}

# ===============================================
# [공용 Secret — data-layer-secrets]
#   → 값은 전부 secrets.auto.tfvars 에서만 들어온다(terraform.tfvars 는 커밋되므로 금지).
#   → kubernetes_manifest 가 아니라 typed 리소스를 쓰는 이유는 매니페스트 전체가 state 에 평문으로 남기 때문.
# ===============================================
resource "kubernetes_secret_v1" "data_layer_secrets" {
  metadata {
    name      = "data-layer-secrets"
    namespace = kubernetes_namespace_v1.data_layer.metadata[0].name
    labels = {
      "app.kubernetes.io/part-of" = "data-layer"
    }
  }

  type = "Opaque"

  data = {
    # MinIO 인증
    MINIO_ROOT_USER         = var.minio_root_user
    MINIO_ROOT_PASSWORD     = var.minio_root_password
    CDM_OBJSTORE_ACCESS_KEY = var.minio_root_user
    CDM_OBJSTORE_SECRET_KEY = var.minio_root_password

    # PostgreSQL 인증
    COLLECTOR_DB_USER     = var.postgres_user
    COLLECTOR_DB_PASSWORD = var.postgres_password

    # Application Key
    COLLECTOR_CRYPTO_KEY = var.collector_crypto_key
    DATA_LAYER_API_KEY   = var.data_layer_api_key

    # Neo4j 인증
    PLATFORM_NEO4J_USER     = var.platform_neo4j_user
    PLATFORM_NEO4J_PASSWORD = var.platform_neo4j_password

    # Grafana 관리자 계정
    GF_SECURITY_ADMIN_USER     = var.grafana_admin_user
    GF_SECURITY_ADMIN_PASSWORD = var.grafana_admin_password
  }
}
