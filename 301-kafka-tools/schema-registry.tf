# ===============================================
# [Schema Registry]
#   → 스키마 본체는 Kafka 의 _schemas 토픽이라 PVC 가 없다 → Deployment(자유 재스케줄).
#   → 브로커보다 먼저 떠도 스스로 재시도하므로 기동 순서를 코드로 강제하지 않는다.
# ===============================================

resource "kubernetes_manifest" "schema_registry_deployment" {
  manifest = yamldecode(templatefile("${path.module}/manifests/schema-registry-deployment.yaml.tftpl", {
    namespace = var.namespace
    image     = "${var.harbor_registry}/data-layer/schema-registry:${var.image_tag}"
    replicas  = var.schema_registry_replicas

    # SCHEMA_REGISTRY_LISTENERS 와 containerPort 가 이 한 값에서 나온다
    http_port = var.schema_registry_port
  }))
}

resource "kubernetes_manifest" "schema_registry_service" {
  manifest = yamldecode(templatefile("${path.module}/manifests/schema-registry-service.yaml.tftpl", {
    namespace = var.namespace
    http_port = var.schema_registry_port
  }))
}
