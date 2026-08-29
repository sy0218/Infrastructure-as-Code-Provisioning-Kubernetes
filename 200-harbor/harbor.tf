# ===============================================
# [Harbor Helm Chart]
#   - Helm으로 Harbor를 설치한다.
#
# → UI / API / Container Registry 등을 함께 구성한다.
# → Ingress를 통해 외부에서 Harbor에 접근한다.
# → Harbor가 사용할 StorageClass는 사전에 생성되어 있어야 한다.
# ===============================================

# -----------------------------------------------
# [배치 노드]
#
# → Harbor 이미지는 tar로 백업하여 MinIO에 보관한다.
# → Harbor 컴포넌트 7개를 단일 노드에 배치해 네트워크 오버헤드를 줄인다.
# → local-path PV가 노드에 종속되므로 노드 변경 시 재설치가 필요하다.
# -----------------------------------------------

locals {
  harbor_node = { "kubernetes.io/hostname" = var.harbor_node_name }
}

resource "helm_release" "harbor" {
  name             = "harbor"
  repository       = "https://helm.goharbor.io"
  chart            = "harbor"
  version          = var.harbor_chart_version
  namespace        = "harbor"
  create_namespace = true
  timeout          = 600

  values = [yamlencode({

    # -----------------------------------------------
    # [외부 접근]
    #
    # → Harbor를 ingress-nginx를 통해 외부에 노출한다.
    # → Harbor Chart가 Ingress 리소스까지 생성한다.
    # → TLS는 사용하지 않고 HTTP로 접근한다.
    # -----------------------------------------------
    expose = {
      type = "ingress"
      tls  = { enabled = false }

      ingress = {
        className = "nginx"
        hosts     = { core = var.harbor_host }

        annotations = {
          # 대용량 이미지 Push 허용
          "nginx.ingress.kubernetes.io/proxy-body-size" = "0"

          # 대용량 업로드 시 요청 버퍼링 비활성화
          "nginx.ingress.kubernetes.io/proxy-request-buffering" = "off"

          # 이미지 Push/Pull 시 충분한 응답 대기 시간 확보
          "nginx.ingress.kubernetes.io/proxy-read-timeout" = var.harbor_proxy_timeout
          "nginx.ingress.kubernetes.io/proxy-send-timeout" = var.harbor_proxy_timeout

          # HTTP → HTTPS 강제 전환 비활성화
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

    # -----------------------------------------------
    # [배치]
    #
    # → 컴포넌트 전체를 var.harbor_node_name 노드 하나에 모은다.
    # -----------------------------------------------
    portal     = { nodeSelector = local.harbor_node }
    core       = { nodeSelector = local.harbor_node }
    jobservice = { nodeSelector = local.harbor_node }
    registry   = { nodeSelector = local.harbor_node }
    database   = { internal = { nodeSelector = local.harbor_node } }
    redis      = { internal = { nodeSelector = local.harbor_node } }

    # -----------------------------------------------
    # [영구 저장소]
    #
    # → Harbor의 PVC를 지정한 StorageClass로 생성한다.
    # → 현재는 local-path를 사용한다.
    #
    # - registry  : 컨테이너 이미지 저장
    # - database  : 프로젝트 / 사용자 / 권한 등 메타데이터
    # - redis     : 세션 / 작업 큐
    # - jobservice: 작업 로그
    # - trivy     : 취약점 DB 캐시
    # -----------------------------------------------
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

        # Redis 세션 / 잡 큐 → 유실돼도 재시작으로 복구된다
        redis = {
          storageClass = var.harbor_storage_class
          size         = var.harbor_component_storage_size
        }

        # Jobservice 작업 로그 → 유실되어도 되는 로그다
        jobservice = {
          jobLog = {
            storageClass = var.harbor_storage_class
            size         = var.harbor_component_storage_size
          }
        }

        # 비워 두면 이 PVC 만 클러스터 기본 StorageClass 로 새어 나간다
        trivy = {
          storageClass = var.harbor_storage_class
          size         = var.harbor_trivy_storage_size
        }
      }
    }

    # -----------------------------------------------
    # [Trivy]
    #
    # → Harbor 이미지의 취약점을 검사한다.
    # → 취약점 DB는 캐시이므로 삭제되어도 재생성할 수 있다.
    # → 아직 수정되지 않은 취약점은 검사 결과에서 제외한다.
    # -----------------------------------------------
    trivy = {
      enabled       = true
      ignoreUnfixed = true

      # 배치는 위 [배치] 섹션과 같다
      nodeSelector = local.harbor_node
    }
  })]
}

# -----------------------------------------------
# [Harbor Core Probe 완화]
#
# → 대용량 이미지 Push 중 Core 응답이 늦어질 수 있다.
# → 이때 Probe timeout으로 Core가 재시작되는 것을 방지한다.
#
# → Harbor Chart 1.18.4에서는 Core Probe 설정을
#    values로 직접 변경하기 어려워 설치 후 kubectl patch로 적용한다.
# → Helm Release가 변경되면 패치를 다시 적용한다.
# -----------------------------------------------

resource "terraform_data" "core_probe_relax" {
  # Harbor Release 변경 시 패치를 다시 실행한다.
  triggers_replace = [helm_release.harbor.metadata.revision]

  provisioner "local-exec" {
    command = <<-EOT
      kubectl --kubeconfig ${pathexpand(var.kubeconfig_path)} -n harbor patch deployment harbor-core --type=json -p='[
        {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/timeoutSeconds","value":5},
        {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":6},
        {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":5}
      ]'
    EOT
  }
}
