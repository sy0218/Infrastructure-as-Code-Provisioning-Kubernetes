# ===============================================
# [MetalLB]
#
# 온프렘 Kubernetes 환경에서
# Service type: LoadBalancer 기능을 제공한다.
#
# 클라우드 환경에서는 AWS/GCP 등의 클라우드 플랫폼이
# LoadBalancer Service에 외부 IP를 자동으로 할당한다.
#
# 하지만 온프렘 환경에는 이 역할을 수행하는 클라우드
# Load Balancer가 없으므로, MetalLB가 외부 IP(VIP) 할당과
# 네트워크 광고 역할을 대신한다.
# ===============================================
# [이 스택의 역할]
#
# → MetalLB 기본 컴포넌트 설치
#
# VIP 대역(IPAddressPool)과 + VIP 광고 방식(L2Advertisement)은
# → 102-ingress 스택에서 별도로 관리한다.
#
# MetalLB CRD가 먼저 설치되어야
# → IPAddressPool / L2Advertisement 리소스를 생성할 수 있다.
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

    # -------------------------------------------
    # [BGP 비활성화]
    #
    # MetalLB는 외부 IP(VIP)를 네트워크에 알리는 방식으로
    # L2 모드와 BGP 모드를 지원한다.
    #
    # 이 프로젝트에서는 L2 모드만 사용하므로 BGP 관련 기능은 필요하지 않다.
    #
    # 따라서 FRR 기반의 BGP 구성요소를 비활성화하여
    # 불필요한 Pod 및 리소스 사용을 방지한다.
    # -------------------------------------------
    frrk8s = {
      enabled = false
    }

    # -------------------------------------------
    # [Controller 리소스]
    #
    # → Controller는 MetalLB 설정을 관리하는 Pod다.
    #     - VIP를 관리하고 할당하는 관리자
    #
    # → 1개만 실행된다.
    #     - Pod가 종료되도 Deployment 컨트롤러가 선언된 상태를 유지합니다.
    #
    # → 매우 가벼운 컴포넌트이므로 필요한 최소 CPU/메모리만 예약한다.
    # -------------------------------------------
    controller = {
      resources = {
        requests = {
          cpu    = "10m"
          memory = "32Mi"
        }
      }
    }

    # -------------------------------------------
    # [Speaker 리소스]
    #
    # → Speaker는 각 Kubernetes 노드마다 1개씩 실행된다. (DaemonSet)
    # → L2 방식에서는 Speaker가 VIP를 네트워크에 광고하는 역할을 한다.
    # → 가벼운 프로세스이므로 필요한 최소 CPU/메모리만 예약한다.
    # -------------------------------------------
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