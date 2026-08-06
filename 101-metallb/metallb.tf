# ===============================================
# [MetalLB — 온프렘 LoadBalancer 구현체]
#   → 클라우드가 아닌 클러스터에는 type: LoadBalancer 에 IP 를 붙여 줄 주체가 없어
#     Service 가 영원히 <pending> 에 머문다. 그 자리를 채우는 컴포넌트다.
#   → 이 스택은 '기능을 켜는' 것까지만 한다. 실제 VIP 대역(IPAddressPool)과 광고 방식
#     (L2Advertisement)은 102-ingress 소유 — CRD 가 생기기 전에는 그 CR 을 plan 조차 할 수 없다.
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
    # ⚠ 차트 기본값이 true 다 — 끄지 않으면 BGP 백엔드(frr-k8s)가 서브차트째 딸려 와
    #   노드마다 FRR 컨테이너가 뜬다. 이 랩은 L2Advertisement 만 쓰므로 순수 낭비다
    #   (노드당 가용 메모리가 2873Mi 뿐이라 무시할 수 있는 크기가 아니다).
    #   BGP 를 쓰려면 이 값을 켜는 것이 아니라 라우터 쪽 설계부터 다시 해야 한다.
    frrk8s = {
      enabled = false
    }

    # speaker 는 노드마다 뜨는 DaemonSet 이고 controller 는 1개다. 둘 다 실사용이
    # 20Mi 를 넘지 않는 경량 프로세스라 요청을 명시해 스케줄러가 과대평가하지 않게 한다.
    controller = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
      }
    }
    speaker = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
      }
    }
  })]
}
