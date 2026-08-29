# ===============================================
# [ingress-nginx]
#
# Kubernetes 클러스터의 HTTP/HTTPS 진입점이다.
#
# 외부 사용자는 Ingress VIP로 접속하고,
# ingress-nginx는 요청의 도메인과 경로에 따라
# 적절한 Kubernetes Service로 요청을 전달한다.
#
# 예)
# example.com/api → api-service
# example.com/web → web-service
#
# Ingress 리소스는 각 애플리케이션 서비스에서 관리하고,
# 이 스택에서는 ingress-nginx Controller만 설치한다.
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

      # Ingress Controller Pod 개수
      replicaCount = var.ingress_replicas

      # -----------------------------------------------
      # [Ingress 외부 접속]
      # -----------------------------------------------

      service = {
        # MetalLB가 VIP를 할당할 수 있도록 Service를 LoadBalancer로 생성한다.
        type = "LoadBalancer"

        # MetalLB가 이 Service에 사용할 VIP를 지정한다.
        annotations = {
          "metallb.io/loadBalancerIPs" = var.ingress_vip
        }

        # 실제 Ingress Controller가 실행 중인 노드에서 외부 트래픽을 처리하도록 한다.
        externalTrafficPolicy = "Local"
      }

      # -----------------------------------------------
      # [파드 노드 분산]
      # -----------------------------------------------

      affinity = {
        podAntiAffinity = {
          # 동일한 Ingress Controller Pod가 하나의 노드에 함께 배치되지 않도록 한다.
          # 노드 장애 시 다른 노드의 Ingress Controller가 계속 요청을 처리할 수 있다.
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

      # -----------------------------------------------
      # [리소스]
      # -----------------------------------------------
      # Ingress Controller가 사용할 최소 리소스를 예약한다.
      resources = {
        requests = {
          cpu    = "50m"
          memory = "128Mi"
        }
      }
    }
  })]

  # LoadBalancer Service가 VIP를 할당받을 수 있도록 MetalLB의 IP Pool과 L2 광고 설정을 먼저 생성한다.
  depends_on = [
    kubernetes_manifest.ingress_vip_pool,
    kubernetes_manifest.ingress_vip_l2advertisement
  ]
}