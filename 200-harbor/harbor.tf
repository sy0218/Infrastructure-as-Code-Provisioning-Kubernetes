# ===============================================
# [Harbor Helm Chart]
#
# → Helm으로 Harbor를 설치한다.
# → Harbor의 UI, API, 이미지 저장소(Registry) 등을 함께 설치한다.
# → Ingress까지 Helm Chart가 직접 만들어서 외부에서 접속할 수 있게 한다.
# → Harbor가 사용할 StorageClass는 100-base에서 미리 만들어져 있어야 한다.
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

    # ===============================================
    # [Harbor 노출 → 차트가 Ingress 까지 소유]
    # → Harbor를 Ingress를 통해 외부에 공개합니다.
    # ===============================================
    expose = {
      type = "ingress"
      tls  = { enabled = false }

      ingress = {
        className = "nginx"
        hosts     = { core = var.harbor_host }

        annotations = {
          # 큰 이미지 업로드 허용
          "nginx.ingress.kubernetes.io/proxy-body-size" = "0"

          # 큰 파일을 Ingress가 임시로 버퍼링하지 않음
          "nginx.ingress.kubernetes.io/proxy-request-buffering" = "off"

          # 느린 환경에서도 timeout 방지
          "nginx.ingress.kubernetes.io/proxy-read-timeout" = var.harbor_proxy_timeout
          "nginx.ingress.kubernetes.io/proxy-send-timeout" = var.harbor_proxy_timeout
          
          # HTTPS로 강제 전환하지 않음
          "ingress.kubernetes.io/ssl-redirect"       = "false"
          "nginx.ingress.kubernetes.io/ssl-redirect" = "false"
        }
      }
    }

    # Docker / containerd가 접속하는 Harbor 주소
    # → Ingress의 host와 반드시 같아야 한다.
    externalURL = "http://${var.harbor_host}"

    # Harbor 관리자 비밀번호
    harborAdminPassword = var.harbor_admin_password

    # ===============================================
    # [영구 저장소]
    #
    # → Registry / Database / Redis는 Longhorn 사용
    #   - Registry : 실제 컨테이너 이미지 저장
    #   - Database : Harbor 메타데이터 저장(프로젝트/사용자/권한 정보)
    #   - Redis    : 노드 장애 시 자동 복구 목적
    #
    # → Jobservice는 잃어도 되는 로그이므로 local-path 사용
    # → Trivy는 재생성 가능한 캐시라 기본 local-path 사용
    #
    # ===============================================
    persistence = {
      persistentVolumeClaim = {

        # 실제 이미지 저장
        registry = {
          storageClass = var.harbor_storage_class
          size         = var.harbor_registry_storage_size
        }

        # 프로젝트 / 사용자 / 권한 등의 메타데이터 저장
        database = {
          storageClass = var.harbor_storage_class
          size         = var.harbor_component_storage_size
        }

        # Redis 데이터 저장
        # → 데이터 보존보다는 노드 장애 시 자동 재배치가 목적
        redis = {
          storageClass = var.harbor_storage_class
          size         = var.harbor_component_storage_size
        }

        # Jobservice 작업 로그
        # → 유실되어도 되므로 local-path 사용
        # → 노드 장애 시 자동 재배치는 되지 않음
        jobservice = {
          jobLog = {
            storageClass = "local-path"
            size         = var.harbor_component_storage_size
          }
        }
      }
    }

    # ===============================================
    # [Trivy]
    #
    # → Harbor 이미지 취약점 검사 기능
    # → 취약점 DB는 캐시이므로 삭제되어도 다시 생성 가능
    #
    # ===============================================
    trivy = {
      enabled       = true
      ignoreUnfixed = true
    }
  })]
}
