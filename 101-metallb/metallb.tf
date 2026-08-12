# ===============================================
# [MetalLB → 온프렘 Kubernetes의 LoadBalancer 구현체]
#
# → 클라우드 환경에서는 AWS/GCP 등이
#   type: LoadBalancer Service에 외부 IP를 자동으로 할당해 준다.
#
# → 온프렘 Kubernetes에는 이런 기능을 해주는 클라우드가 없기 때문에
#   LoadBalancer Service를 만들어도 외부 IP가 자동으로 할당되지 않는다.
#
# → MetalLB가 이 역할을 대신한다.
#
# 이 스택의 역할
# → MetalLB의 기본 기능만 설치한다.

# → 실제로 사용할 VIP 대역(IPAddressPool)과
#   VIP를 네트워크에 알리는 방법(L2Advertisement)은
#   102-ingress에서 설정한다.
#
# → MetalLB의 CRD가 먼저 설치되어야
#   IPAddressPool / L2Advertisement 리소스를 생성할 수 있다.
# ===============================================

resource "helm_release" "metallb" {
  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  version          = var.metallb_chart_version
  namespace        = var.namespace
  create_namespace = true
  timeout          = 600

  values = [yamlencode({

    # ===========================================
    # [BGP 비활성화]
    #
    # → MetalLB는 L2 방식과 BGP 방식으로 외부 IP(VIP)를 광고할 수 있다.
    # → 이 환경에서는 L2 방식만 사용하므로 BGP 기능은 끈다.
    # → 기본값을 그대로 두면 FRR 기반 BGP 구성요소가
    #   함께 배포될 수 있으므로 불필요한 리소스를 사용하게 된다.
    # ===========================================
    frrk8s = {
      enabled = false
    }

    # ===========================================
    # [Controller 리소스]
    #
    # → Controller는 MetalLB 설정을 관리하는 Pod다.
    # → 1개만 실행된다.
    # → 매우 가벼운 컴포넌트이므로 필요한 최소 CPU/메모리만 예약한다.
    # ===========================================
    controller = {
      resources = {
        requests = {
          cpu    = "10m"
          memory = "32Mi"
        }
      }
    }

    # ===========================================
    # [Speaker 리소스]
    #
    # → Speaker는 각 Kubernetes 노드마다 1개씩 실행된다. (DaemonSet)
    # → L2 방식에서는 Speaker가 VIP를 네트워크에 광고하는 역할을 한다.
    # → 가벼운 프로세스이므로 필요한 최소 CPU/메모리만 예약한다.
    # ===========================================
    speaker = {
      resources = {
        requests = {
          cpu    = "10m"
          memory = "32Mi"
        }
      }
    }
  })]
}