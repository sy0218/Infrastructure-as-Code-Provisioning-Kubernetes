# ===============================================
# [cdc-oracle — CDC 소스 RDB]
#   → Debezium OracleConnector 가 LogMiner 로 redo 로그를 읽는다. 넷 중 전제조건이 가장 많고
#     하나라도 빠지면 태스크가 기동 직후 죽는다:
#       ARCHIVELOG · FORCE LOGGING           → 이미지 env (STS)
#       FRA(아카이브 목적지)                  → 이미지가 ARCHIVELOG 와 함께 잡는다
#       DB 최소 보충로깅 · 테이블 ALL COLUMNS → initdb 스크립트
#       c##dbzuser(공통유저) + LOGMINER_TBS   → initdb 스크립트
# ===============================================

locals {
  # 이미지의 ORACLE_BASE/oradata — STS 의 볼륨 마운트 경로와 같아야 한다(둘이 한 쌍).
  oracle_oradata_path = "/opt/oracle/oradata"

  oracle_initdb_sh = templatefile("${path.module}/manifests/oracle-initdb.sh.tftpl", {
    cdb_name             = var.oracle_cdb_name
    pdb_name             = var.oracle_pdb_name
    app_user             = var.oracle_app_user
    dbz_user             = var.oracle_dbz_user
    sga_target           = var.oracle_sga_target
    pga_aggregate_target = var.oracle_pga_aggregate_target
    oradata_path         = local.oracle_oradata_path
  })
}

# ⚠ 볼륨이 빈 첫 기동에만 실행된다 → 내용을 고쳐도 롤아웃만으로는 반영되지 않는다.
#   스키마·권한을 바꾸려면 PVC(data-cdc-oracle-0)를 지우고 다시 만들어야 한다.
resource "kubernetes_config_map_v1" "oracle_initdb" {
  metadata {
    name      = "cdc-oracle-initdb"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"      = "cdc-oracle"
      "app.kubernetes.io/component" = "test-rdb"
      "app.kubernetes.io/part-of"   = "data-layer"
    }
  }

  data = {
    "01_cdc_setup.sh" = local.oracle_initdb_sh
  }
}

resource "kubernetes_manifest" "oracle_statefulset" {
  manifest = yamldecode(templatefile("${path.module}/manifests/oracle-statefulset.yaml.tftpl", {
    namespace      = var.namespace
    image          = "${var.harbor_registry}/data-layer/test-rdb-oracle:${var.image_tag}"
    port           = var.oracle_port
    app_user       = var.oracle_app_user
    storage_class  = var.test_rdb_storage_class
    storage_size   = var.oracle_storage_size
    cpu_request    = var.oracle_cpu_request
    memory_request = var.oracle_memory_request
  }))

  depends_on = [
    kubernetes_config_map_v1.oracle_initdb,
    kubernetes_secret_v1.test_rdb,
  ]
}

resource "kubernetes_manifest" "oracle_service" {
  manifest = yamldecode(templatefile("${path.module}/manifests/oracle-service.yaml.tftpl", {
    namespace = var.namespace
    port      = var.oracle_port
  }))
}
