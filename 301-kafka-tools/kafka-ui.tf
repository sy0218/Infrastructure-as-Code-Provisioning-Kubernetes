# ===============================================
# [Kafka UI]
#   → 브로커·토픽·컨슈머 그룹을 들여다보는 웹 콘솔. 외부 노출은 Ingress 하나뿐이다.
#   ⚠ 공용 ConfigMap 키 3개를 configMapKeyRef 로 직접 읽는다(optional 아님) —
#     300-data-layer-base 가 먼저 apply 돼 있지 않으면 CreateContainerConfigError 로 뜨지 못한다.
# ===============================================

resource "kubernetes_manifest" "kafka_ui_deployment" {
  manifest = yamldecode(templatefile("${path.module}/manifests/kafka-ui-deployment.yaml.tftpl", {
    namespace = var.namespace
    image     = "${var.harbor_registry}/data-layer/kafka-ui:${var.image_tag}"

    # SERVER_PORT 와 containerPort 가 이 한 값에서 나온다
    http_port = var.kafka_ui_port

    # 공용 ConfigMap 의 소비 키가 바뀌면 해시가 바뀌어 롤아웃된다 (locals.tf)
    config_hash = local.kafka_ui_config_hash
  }))
}

resource "kubernetes_manifest" "kafka_ui_service" {
  manifest = yamldecode(templatefile("${path.module}/manifests/kafka-ui-service.yaml.tftpl", {
    namespace = var.namespace
    http_port = var.kafka_ui_port
  }))
}

# 브라우저 진입점 — 102-ingress 의 VIP 가 Host 헤더로 이 규칙을 찾는다
resource "kubernetes_manifest" "kafka_ui_ingress" {
  manifest = yamldecode(templatefile("${path.module}/manifests/kafka-ui-ingress.yaml.tftpl", {
    namespace = var.namespace
    host      = var.kafka_ui_host
    http_port = var.kafka_ui_port
  }))

  # 백엔드가 없는 Ingress 는 502 를 돌려준다(오브젝트 생성 자체는 성공해서 더 헷갈린다)
  depends_on = [kubernetes_manifest.kafka_ui_service]
}
