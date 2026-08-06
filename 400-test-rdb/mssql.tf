# ===============================================
# [cdc-mssql — CDC 소스 RDB]
#   → 넷 중 유일하게 로그를 직접 읽지 않는다. SQL Agent 잡(cdc_capture)이 변경분을 cdc.* 테이블로
#     옮기고 Debezium 은 그것을 폴링한다 → Agent 가 멈추면 캡처 자체가 멈춘다.
#   → 그래서 이 스택이 책임지는 것도 둘로 나뉜다:
#       STS  = Agent 켜기(MSSQL_AGENT_ENABLED) + 서버 기동
#       Job  = 스키마 + sp_cdc_enable_db/table   (이미지에 초기화 훅이 없다)
# ===============================================

locals {
  mssql_image = "${var.harbor_registry}/data-layer/test-rdb-mssql:${var.image_tag}"

  mssql_initdb_sql = templatefile("${path.module}/manifests/mssql-initdb.sql.tftpl", {
    database = var.mssql_database
  })

  # Job spec 은 불변이라 같은 이름으로 다시 apply 할 수 없다 → 이름에 스크립트 해시를 넣는다.
  # 스크립트를 고치면 이름이 바뀌어 새 Job 이 한 번 더 돌고, 안 고치면 아무 일도 일어나지 않는다.
  # (다른 셋은 이미지 훅이라 PVC 를 지워야 다시 도는데, 이쪽만 이 방식으로 재실행이 가능하다.)
  mssql_init_job_name = "cdc-mssql-init-${substr(sha256(local.mssql_initdb_sql), 0, 8)}"
}

resource "kubernetes_config_map_v1" "mssql_initdb" {
  metadata {
    name      = "cdc-mssql-initdb"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"      = "cdc-mssql"
      "app.kubernetes.io/component" = "test-rdb"
      "app.kubernetes.io/part-of"   = "data-layer"
    }
  }

  data = {
    "01_cdc_test_qm_qc_result.sql" = local.mssql_initdb_sql
  }
}

resource "kubernetes_manifest" "mssql_statefulset" {
  manifest = yamldecode(templatefile("${path.module}/manifests/mssql-statefulset.yaml.tftpl", {
    namespace       = var.namespace
    image           = local.mssql_image
    port            = var.mssql_port
    edition         = var.mssql_edition
    memory_limit_mb = var.mssql_memory_limit_mb
    storage_class   = var.test_rdb_storage_class
    storage_size    = var.mssql_storage_size
    cpu_request     = var.mssql_cpu_request
    memory_request  = var.mssql_memory_request
  }))

  depends_on = [kubernetes_secret_v1.test_rdb]
}

resource "kubernetes_manifest" "mssql_service" {
  manifest = yamldecode(templatefile("${path.module}/manifests/mssql-service.yaml.tftpl", {
    namespace = var.namespace
    port      = var.mssql_port
  }))
}

resource "kubernetes_manifest" "mssql_init_job" {
  manifest = yamldecode(templatefile("${path.module}/manifests/mssql-init-job.yaml.tftpl", {
    namespace  = var.namespace
    job_name   = local.mssql_init_job_name
    image      = local.mssql_image
    database   = var.mssql_database
    mssql_host = "cdc-mssql.${var.namespace}.svc.cluster.local"
    mssql_port = var.mssql_port
  }))

  # ⚠ Job 컨트롤러가 파드 템플릿에 라벨 4종(controller-uid·job-name 및 batch.kubernetes.io/ 접두)을
  #   생성 시점에 붙인다 — UUID 라서 매니페스트에 미리 적을 수 없고, 그대로 두면 apply 가
  #   "unexpected new value: new element ... has appeared" 로 실패한다(304-airflow 와 같은 장치).
  computed_fields = [
    "metadata.annotations",
    "metadata.labels",
    "spec.template.metadata.labels",
  ]

  # 서버 Service 가 없으면 파드 안 대기 루프가 DNS 부터 실패해 backoffLimit 을 그냥 태운다.
  depends_on = [
    kubernetes_config_map_v1.mssql_initdb,
    kubernetes_secret_v1.test_rdb,
    kubernetes_manifest.mssql_service,
    kubernetes_manifest.mssql_statefulset,
  ]
}
