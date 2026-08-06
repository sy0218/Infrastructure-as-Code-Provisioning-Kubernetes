# ===============================================
# [Grafana]
#   → 데이터소스/대시보드 프로비저닝은 이미지에 구워져 있어 여기서 주입하지 않는다.
#   → 데이터소스가 가리키는 곳은 클러스터 내부 주소(prometheus:9090)다 — 인그레스로
#     열었다고 외부 이름으로 바꾸면 안 된다(그 이름은 파드 안에서 해석되지 않는다).
# ===============================================

resource "kubernetes_manifest" "grafana_pvc" {
  manifest = yamldecode(templatefile("${path.module}/manifests/grafana-pvc.yaml.tftpl", {
    namespace     = var.namespace
    storage_size  = var.grafana_storage_size
    storage_class = var.grafana_storage_class
  }))
}

resource "kubernetes_manifest" "grafana_deployment" {
  manifest = yamldecode(templatefile("${path.module}/manifests/grafana-deployment.yaml.tftpl", {
    namespace    = var.namespace
    image        = "${var.harbor_registry}/data-layer/grafana:${var.image_tag}"
    grafana_port = var.grafana_port
  }))

  # PVC 가 없으면 파드가 볼륨 마운트 단계에서 멈춘다
  depends_on = [kubernetes_manifest.grafana_pvc]
}

resource "kubernetes_manifest" "grafana_service" {
  manifest = yamldecode(templatefile("${path.module}/manifests/grafana-service.yaml.tftpl", {
    namespace    = var.namespace
    grafana_port = var.grafana_port
  }))
}

# 브라우저·iframe 진입점 — 102-ingress 의 VIP 가 Host 헤더로 이 규칙을 찾는다
resource "kubernetes_manifest" "grafana_ingress" {
  manifest = yamldecode(templatefile("${path.module}/manifests/grafana-ingress.yaml.tftpl", {
    namespace    = var.namespace
    host         = var.grafana_host
    grafana_port = var.grafana_port
  }))

  # 백엔드가 없는 Ingress 는 502 를 돌려준다(오브젝트 생성 자체는 성공해서 더 헷갈린다)
  depends_on = [kubernetes_manifest.grafana_service]
}
