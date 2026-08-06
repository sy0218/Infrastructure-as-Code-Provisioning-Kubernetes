# ===============================================
# [Prometheus]
#   → 공식 이미지(Harbor 미러) + ConfigMap 직접 구성 — 차트를 쓰지 않는다.
#   → 클러스터 안 타깃은 kubernetes_sd 가 런타임에 채우고, 클러스터 밖 로컬 Kafka
#     브로커(:9404)만 static 타깃이다(kafka_jmx_targets).
# ===============================================

locals {
  # 렌더 결과를 한 번만 만들어 ConfigMap 과 파드 템플릿의 checksum 두 곳에서 쓴다.
  # templatefile 을 두 번 호출하면 인자 한쪽만 고쳤을 때 "롤아웃은 됐는데 설정은 그대로"가 된다.
  prometheus_config_rendered = templatefile("${path.module}/manifests/prometheus-config.yaml.tftpl", {
    namespace                   = var.namespace
    global_scrape_interval      = var.global_scrape_interval
    kafka_jmx_targets           = var.kafka_jmx_targets
    alloy_node_metrics_path     = var.alloy_node_metrics_path
    alloy_cadvisor_metrics_path = var.alloy_cadvisor_metrics_path
  })
}

# ConfigMap 이지만 typed 가 아니라 kubernetes_manifest 를 쓴다 — 스크랩 설정에는 시크릿이
# 없고, YAML 파일로 두어야 relabel 규칙의 들여쓰기가 눈에 보인다.
resource "kubernetes_manifest" "prometheus_config" {
  manifest = yamldecode(local.prometheus_config_rendered)
}

resource "kubernetes_manifest" "prometheus_statefulset" {
  manifest = yamldecode(templatefile("${path.module}/manifests/prometheus-statefulset.yaml.tftpl", {
    namespace       = var.namespace
    image           = "${var.harbor_registry}/data-layer/prometheus:${var.image_tag}"
    retention       = var.prometheus_retention
    storage_size    = var.prometheus_storage_size
    storage_class   = var.prometheus_storage_class
    prometheus_port = var.prometheus_port

    # 설정이 바뀌면 이 해시가 바뀌어 파드가 스스로 롤아웃된다
    config_hash = sha256(local.prometheus_config_rendered)
  }))

  # ConfigMap 이 없으면 파드가 볼륨 마운트 실패로 ContainerCreating 에서 멈춘다.
  # SD 용 API 권한은 300-data-layer-base 의 바인딩이 default SA 에 이미 주고 있다(스택이 달라 depends_on 불가).
  depends_on = [
    kubernetes_manifest.prometheus_config,
  ]
}

resource "kubernetes_manifest" "prometheus_service" {
  manifest = yamldecode(templatefile("${path.module}/manifests/prometheus-service.yaml.tftpl", {
    namespace       = var.namespace
    prometheus_port = var.prometheus_port
  }))
}

# 타깃 상태/PromQL 을 직접 보는 디버깅 UI 를 Grafana 와 같은 방식(Ingress)으로 연다
resource "kubernetes_manifest" "prometheus_ingress" {
  manifest = yamldecode(templatefile("${path.module}/manifests/prometheus-ingress.yaml.tftpl", {
    namespace       = var.namespace
    host            = var.prometheus_host
    prometheus_port = var.prometheus_port
  }))

  # 백엔드가 없는 Ingress 는 502 를 돌려준다(오브젝트 생성 자체는 성공해서 더 헷갈린다)
  depends_on = [kubernetes_manifest.prometheus_service]
}
