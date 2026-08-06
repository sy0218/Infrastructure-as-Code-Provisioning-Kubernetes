# ===============================================
# [cdc-mysql — CDC 소스 RDB]
#   → Debezium MySqlConnector 가 복제 클라이언트로 붙어 binlog 를 읽는다.
#   → 전제조건은 둘로 나뉜다: 서버 옵션(ROW/FULL/server-id)은 STS args,
#     복제 권한(REPLICATION SLAVE/CLIENT)은 initdb 스크립트 — 이미지가 주는 권한은
#     자기 DB 한정이라 전역 권한을 따로 얹어야 한다.
# ===============================================

locals {
  mysql_initdb_sql = templatefile("${path.module}/manifests/mysql-initdb.sql.tftpl", {
    database = var.mysql_database
    user     = var.mysql_user
  })
}

# ⚠ 볼륨이 빈 첫 기동에만 실행된다 → 내용을 고쳐도 롤아웃만으로는 반영되지 않는다.
#   스키마를 바꾸려면 PVC(data-cdc-mysql-0)를 지우고 다시 만들어야 한다.
resource "kubernetes_config_map_v1" "mysql_initdb" {
  metadata {
    name      = "cdc-mysql-initdb"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"      = "cdc-mysql"
      "app.kubernetes.io/component" = "test-rdb"
      "app.kubernetes.io/part-of"   = "data-layer"
    }
  }

  data = {
    "01_cdc_test_qm_batches.sql" = local.mysql_initdb_sql
  }
}

resource "kubernetes_manifest" "mysql_statefulset" {
  manifest = yamldecode(templatefile("${path.module}/manifests/mysql-statefulset.yaml.tftpl", {
    namespace             = var.namespace
    image                 = "${var.harbor_registry}/data-layer/test-rdb-mysql:${var.image_tag}"
    port                  = var.mysql_port
    database              = var.mysql_database
    user                  = var.mysql_user
    server_id             = var.mysql_server_id
    binlog_expire_seconds = var.mysql_binlog_expire_seconds
    storage_class         = var.test_rdb_storage_class
    storage_size          = var.mysql_storage_size
    cpu_request           = var.mysql_cpu_request
    memory_request        = var.mysql_memory_request
  }))

  depends_on = [
    kubernetes_config_map_v1.mysql_initdb,
    kubernetes_secret_v1.test_rdb,
  ]
}

resource "kubernetes_manifest" "mysql_service" {
  manifest = yamldecode(templatefile("${path.module}/manifests/mysql-service.yaml.tftpl", {
    namespace = var.namespace
    port      = var.mysql_port
  }))
}
