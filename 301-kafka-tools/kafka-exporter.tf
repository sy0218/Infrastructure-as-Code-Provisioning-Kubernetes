# ===============================================
# [Kafka Exporter]
#   → 토픽·오프셋·Consumer Lag 을 Prometheus 메트릭으로 노출한다.
#   → 브로커 JVM 메트릭은 브로커 안 javaagent 담당이라 여기서 다루지 않는다.
# ===============================================

resource "kubernetes_manifest" "kafka_exporter_deployment" {
  manifest = yamldecode(templatefile("${path.module}/manifests/kafka-exporter-deployment.yaml.tftpl", {
    namespace = var.namespace
    image     = "${var.harbor_registry}/data-layer/kafka-exporter:${var.image_tag}"

    # 리슨 주소·containerPort 가 이 한 값에서 나온다
    exporter_port = var.kafka_exporter_port

    # 공용 ConfigMap 의 소비 키가 바뀌면 해시가 바뀌어 롤아웃된다 (locals.tf)
    config_hash = local.kafka_exporter_config_hash
  }))
}

resource "kubernetes_manifest" "kafka_exporter_service" {
  manifest = yamldecode(templatefile("${path.module}/manifests/kafka-exporter-service.yaml.tftpl", {
    namespace     = var.namespace
    exporter_port = var.kafka_exporter_port
  }))
}
