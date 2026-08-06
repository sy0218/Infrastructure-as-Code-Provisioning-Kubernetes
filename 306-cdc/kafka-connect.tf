# ===============================================
# [Kafka Connect (Debezium)]
#   → 소스 RDB 의 변경로그를 raw.* 토픽으로 흘리는 워커 묶음.
#   → 상태를 파드에 두지 않으므로(설정/오프셋/상태 = Kafka 내부 토픽) StatefulSet 이 아니라 Deployment ×N 이다.
#   → 워커가 죽으면 커밋된 오프셋부터 다른 워커가 이어받는다(at-least-once — 중복은 하류 upsert 가 흡수).
# ===============================================

locals {
  connect_image = "${var.harbor_registry}/data-layer/kafka-connect:${var.image_tag}"
}

resource "kubernetes_manifest" "cdc_connect_deployment" {
  manifest = yamldecode(templatefile("${path.module}/manifests/cdc-connect-deployment.yaml.tftpl", {
    namespace            = var.namespace
    image                = local.connect_image
    replicas             = var.connect_replicas
    rest_port            = var.connect_rest_port
    group_id             = var.connect_group_id
    config_storage_topic = var.connect_config_storage_topic
    offset_storage_topic = var.connect_offset_storage_topic
    status_storage_topic = var.connect_status_storage_topic
    replication_factor   = var.connect_replication_factor

    # 공용 ConfigMap 의 브로커 주소가 바뀌면 해시가 바뀌어 롤아웃된다 (locals.tf)
    config_hash = local.connect_config_hash
  }))
}

# 워커 3개 중 아무나 받으면 되는 REST 창구(비리더는 리더에게 포워딩한다)
resource "kubernetes_manifest" "cdc_connect_service" {
  manifest = yamldecode(templatefile("${path.module}/manifests/cdc-connect-service.yaml.tftpl", {
    namespace = var.namespace
    rest_port = var.connect_rest_port
  }))
}
