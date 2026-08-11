# ===============================================
# [ingress-nginx → HTTP 진입점]
#
# → 브라우저 요청을 받아 각 Kubernetes Service로 전달한다.
# → 사용자는 VIP 하나만 접속하면 된다.
# → 서비스가 늘어나도 외부에서 사용하는 포트는 그대로다.
#
# → Ingress 리소스는 각 애플리케이션 스택에서 관리한다.
# → 여기서는 ingress-nginx 자체만 설치한다.
# ===============================================

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version
  namespace        = "ingress-nginx"
  create_namespace = true
  timeout          = 600

  values = [yamlencode({
    controller = {
      replicaCount = var.ingress_replicas

      # ===============================================
      # [Ingress 외부 접속]
      # ===============================================

      service = {
        # → MetalLB가 VIP를 할당할 수 있도록 LoadBalancer로 생성한다.
        type = "LoadBalancer"

        # → MetalLB에 사용할 VIP를 지정한다.
        # → 별도로 만든 IPAddressPool의 VIP와 동일해야 한다.
        annotations = {
          "metallb.io/loadBalancerIPs" = var.ingress_vip
        }

        # → 클라이언트의 원래 IP를 보존한다.
        # → MetalLB L2에서도 실제 Ingress 파드가 있는 노드만
        #   VIP를 광고하도록 한다.
        externalTrafficPolicy = "Local"
      }

      # ===============================================
      # [파드 노드 분산]
      # ===============================================

      # → Ingress 파드가 같은 노드에 몰리지 않도록 한다.
      # → 노드 하나가 장애나도 다른 노드의 Ingress가 요청을 처리한다.
      affinity = {
        podAntiAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = [{
            labelSelector = {
              matchLabels = {
                "app.kubernetes.io/name"      = "ingress-nginx"
                "app.kubernetes.io/instance"  = "ingress-nginx"
                "app.kubernetes.io/component" = "controller"
              }
            }
            topologyKey = "kubernetes.io/hostname"
          }]
        }
      }

      # ===============================================
      # [리소스]
      # ===============================================

      # → 랩 환경에서 필요한 최소한의 CPU/메모리만 예약한다.
      resources = {
        requests = {
          cpu    = "50m"
          memory = "128Mi"
        }
      }
    }
  })]

  # → ingress-nginx를 설치하기 전에
  #   MetalLB의 VIP Pool과 L2 광고 설정이 먼저 있어야 한다.
  #
  # → 이것들이 없으면 LoadBalancer Service가 VIP를 받지 못해
  #   Helm 설치가 timeout으로 실패할 수 있다.
  depends_on = [
    kubernetes_manifest.ingress_vip_pool,
    kubernetes_manifest.ingress_vip_l2advertisement
  ]
}