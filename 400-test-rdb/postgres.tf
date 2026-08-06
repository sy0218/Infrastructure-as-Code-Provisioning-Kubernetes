# ===============================================
# [cdc-postgres — CDC 소스 RDB]
#   → Debezium PostgresConnector 가 pgoutput 으로 WAL 을 읽는다(플러그인 설치 불필요).
#   → 전제조건 셋 중 둘은 여기 있다: wal_level=logical(STS args) · publication(initdb).
#     나머지 하나인 REPLICATION 권한은 이미지가 POSTGRES_USER 를 슈퍼유저로 만들어 자동 충족된다.
# ===============================================

locals {
  postgres_initdb_sql = templatefile("${path.module}/manifests/postgres-initdb.sql.tftpl", {
    publication = var.postgres_publication
  })
}

# ⚠ 이 스크립트는 볼륨이 빈 첫 기동에만 실행된다 → 내용을 고쳐도 롤아웃만으로는 반영되지 않는다.
#   그래서 다른 스택처럼 checksum 어노테이션으로 파드를 흔들지 않는다(흔들어 봐야 소용이 없다).
#   스키마를 바꾸려면 PVC(data-cdc-postgres-0)를 지우고 다시 만들어야 한다.
resource "kubernetes_config_map_v1" "postgres_initdb" {
  metadata {
    name      = "cdc-postgres-initdb"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"      = "cdc-postgres"
      "app.kubernetes.io/component" = "test-rdb"
      "app.kubernetes.io/part-of"   = "data-layer"
    }
  }

  data = {
    "01_cdc_test_qm_event.sql" = local.postgres_initdb_sql
  }
}

resource "kubernetes_manifest" "postgres_statefulset" {
  manifest = yamldecode(templatefile("${path.module}/manifests/postgres-statefulset.yaml.tftpl", {
    namespace      = var.namespace
    image          = "${var.harbor_registry}/data-layer/test-rdb-postgres:${var.image_tag}"
    port           = var.postgres_port
    database       = var.postgres_database
    user           = var.postgres_user
    storage_class  = var.test_rdb_storage_class
    storage_size   = var.postgres_storage_size
    cpu_request    = var.postgres_cpu_request
    memory_request = var.postgres_memory_request
  }))

  # 둘 다 없으면 파드가 볼륨/env 단계에서 멈춘다(ContainerCreating · CreateContainerConfigError)
  depends_on = [
    kubernetes_config_map_v1.postgres_initdb,
    kubernetes_secret_v1.test_rdb,
  ]
}

resource "kubernetes_manifest" "postgres_service" {
  manifest = yamldecode(templatefile("${path.module}/manifests/postgres-service.yaml.tftpl", {
    namespace = var.namespace
    port      = var.postgres_port
  }))
}
