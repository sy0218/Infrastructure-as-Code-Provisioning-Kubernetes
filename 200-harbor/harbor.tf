# ===============================================
# [Harbor Helm Chart]
#   → core(API) / portal(UI) / registry / database / redis / jobservice 를 한 번에 설치한다.
#   → 100-base 의 StorageClass 가 먼저 있어야 하며, 순서는 디렉토리 번호로 관리한다.
# ===============================================
resource "helm_release" "harbor" {
  name             = "harbor"
  repository       = "https://helm.goharbor.io"
  chart            = "harbor"
  version          = var.harbor_chart_version
  namespace        = "harbor"
  create_namespace = true
  timeout          = 600

  values = [yamlencode({

    # 차트는 Service 까지만 만들고 노출은 우리 Ingress 가 맡는다(harbor-ingress.yaml.tftpl).
    # 차트의 expose.type = "ingress" 를 쓰지 않는 이유: 어노테이션이 values 안에 숨어
    # 이 저장소의 "노출은 매니페스트가 소유한다" 규약과 어긋난다.
    expose = {
      type = "clusterIP"
      tls  = { enabled = false }
      clusterIP = {
        name  = "harbor"
        ports = { httpPort = var.harbor_port }
      }
    }

    # docker/containerd 가 실제로 접속하는 주소 — Ingress 의 host 와 반드시 일치해야
    # docker login / push 가 동작한다. 포트가 없는 것은 인그레스가 VIP 의 80 을 쓰기 때문이다.
    externalURL = "http://${var.harbor_host}"

    harborAdminPassword = var.harbor_admin_password

    # 영구 저장소 — Harbor 는 스스로 데이터를 복제하지 않으므로 local-path 가 아니라 Longhorn 을 쓴다.
    # local-path 는 특정 노드에 묶여 그 노드가 죽으면 재배치가 안 되고,
    # Harbor 가 멈추면 전 스택의 image pull 이 함께 멈춘다.
    persistence = {
      persistentVolumeClaim = {

        # 이미지 레이어 본체
        registry = {
          storageClass = var.harbor_storage_class
          size         = var.harbor_registry_storage_size
        }

        # 프로젝트/사용자/권한 등 메타데이터
        database = {
          storageClass = var.harbor_storage_class
          size         = var.harbor_component_storage_size
        }

        # 내부 캐시
        redis = {
          storageClass = var.harbor_storage_class
          size         = var.harbor_component_storage_size
        }

        # 이미지 작업 로그
        jobservice = {
          jobLog = {
            storageClass = var.harbor_storage_class
            size         = var.harbor_component_storage_size
          }
        }
      }
    }

    # 이미지 취약점 스캐너
    # 이미지 취약점 스캔. PVC(취약점 DB 캐시)는 위 persistence 블록에 없어 기본 SC(local-path)로
    # 떨어진다 — 노드에 묶이지만 지워져도 재다운로드되는 캐시라 그대로 둔다.
    trivy = {
      enabled       = true
      ignoreUnfixed = true
    }
  })]
}

# 브라우저·docker·containerd 가 모두 이 규칙으로 들어온다 — 노출 구조는 매니페스트 배너 참조
resource "kubernetes_manifest" "harbor_ingress" {
  manifest = yamldecode(templatefile("${path.module}/manifests/harbor-ingress.yaml.tftpl", {
    namespace     = helm_release.harbor.namespace
    host          = var.harbor_host
    harbor_port   = var.harbor_port
    proxy_timeout = var.harbor_proxy_timeout
  }))

  # 차트가 Service 를 만든 뒤여야 백엔드가 존재한다(없으면 502 를 돌려준다)
  depends_on = [helm_release.harbor]
}
