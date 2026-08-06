# ===============================================
# [Lineage Consumer]
#   → lineage-topic → 로컬 PostgreSQL(data_pipeline.data_lineage). DSN 은 공용 ConfigMap 의 LINEAGE_PG_DSN 이다.
#   → 본 데이터 경로와 토픽·컨슈머 그룹이 분리돼 있어 계보 DB 장애가 파이프라인 정지로 번지지 않는다 — 그래서 별도 워크로드다.
# ===============================================
resource "kubernetes_manifest" "cdm_lineage_consumer" {
  manifest = yamldecode(templatefile("${path.module}/manifests/cdm-lineage-consumer.yaml.tftpl", {
    namespace = var.namespace
    image     = "${var.harbor_registry}/data-layer/cdm-lineage-consumer:${var.image_tag}"
    # 계보 이벤트는 양이 적고 순서 보장 요구도 없다 → 1개로 충분(상한은 lineage-topic 파티션 수)
    replicas                  = 1
    termination_grace_seconds = var.cdm_consumer_termination_grace_seconds
  }))
}
