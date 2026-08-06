# ===============================================
# [Data Layer API + 관리 화면]
#   → 한 프로세스가 "/" 로 관리 화면(정적 파일)을, "/api" 로 REST 를 서빙한다
#     → 동일 출처라 CORS 도, 화면 전용 웹서버 워크로드도 없다.
#   → 상태가 파드 밖에 있어(DQ 규칙·도메인 설정=MinIO, collect_job=PostgreSQL) PVC 없는 Deployment 로 충분하다.
# ===============================================

resource "kubernetes_manifest" "api_deployment" {
  manifest = yamldecode(templatefile("${path.module}/manifests/api-deployment.yaml.tftpl", {
    namespace = var.namespace
    image     = "${var.harbor_registry}/data-layer/api:${var.image_tag}"
    replicas  = var.api_replicas

    # containerPort 와 DATA_LAYER_API_PORT 가 이 한 값에서 나온다
    api_port = var.api_port

    # 파드가 GRAFANA_URL 의 호스트명을 풀기 위한 /etc/hosts 1줄 (variables.tf 배너 참조)
    ingress_vip  = var.ingress_vip
    grafana_host = var.grafana_host
  }))
}

resource "kubernetes_manifest" "api_service" {
  manifest = yamldecode(templatefile("${path.module}/manifests/api-service.yaml.tftpl", {
    namespace = var.namespace
    api_port  = var.api_port
  }))
}

# 브라우저 진입점 — 102-ingress 의 VIP 가 Host 헤더로 이 규칙을 찾는다
resource "kubernetes_manifest" "api_ingress" {
  manifest = yamldecode(templatefile("${path.module}/manifests/api-ingress.yaml.tftpl", {
    namespace          = var.namespace
    host               = var.api_host
    api_port           = var.api_port
    proxy_body_size    = var.api_proxy_body_size
    proxy_read_timeout = var.api_proxy_read_timeout
  }))

  # 백엔드가 없는 Ingress 는 502 를 돌려준다(오브젝트 생성 자체는 성공해서 더 헷갈린다)
  depends_on = [kubernetes_manifest.api_service]
}
