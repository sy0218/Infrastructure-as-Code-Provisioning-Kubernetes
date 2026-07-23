# Harbor 레지스트리 — 공식 차트 하나로 core/portal/registry/jobservice/db/redis 전부 배포
# 선행 조건: 001-base 가 먼저 apply 되어 기본 StorageClass(local-path)가 있어야
# Harbor 의 PVC 4개(registry/db/redis/jobservice)가 바인딩된다.
# (다른 state 의 리소스라 depends_on 으로 못 걸고, 디렉토리 번호 순서가 그 역할을 한다)
resource "helm_release" "harbor" {
  name             = "harbor"
  repository       = "https://helm.goharbor.io"
  chart            = "harbor"
  version          = var.harbor_chart_version
  namespace        = "harbor"
  create_namespace = true
  timeout          = 600

  values = [yamlencode({
    # lab 환경: TLS 없이 NodePort 로 노출 — push/pull 주소는 http://<노드IP>:<NodePort>
    expose = {
      type = "nodePort"
      tls  = { enabled = false }
      nodePort = {
        ports = { http = { nodePort = var.harbor_nodeport } }
      }
    }
    # docker/containerd 가 리다이렉트 받는 기준 주소 — 실제 접속 주소와 반드시 일치해야 함
    externalURL = "http://${var.harbor_external_ip}:${var.harbor_nodeport}"

    harborAdminPassword = var.harbor_admin_password

    persistence = {
      persistentVolumeClaim = {
        registry = { size = var.harbor_registry_storage_size }
      }
    }

    # 취약점 스캐너 — 레지스트리 용도만 쓸 거라 제외 (필요해지면 true)
    trivy = { enabled = false }
  })]
}
