# ===============================================
# [ingress-nginx — HTTP 진입점 하나]
#   → VIP:80 으로 들어온 요청을 Host 헤더로 갈라 각 앱 Service 로 넘긴다. 덕분에
#     브라우저 주소에서 포트가 사라지고, 서비스가 늘어도 열리는 포트는 그대로다.
#   → Ingress 오브젝트 자체는 여기서 만들지 않는다 — 각 앱 스택이 자기 노출을 소유한다.
#   ⚠ 인그레스에 태울 수 없는 것은 git(30418) 하나뿐이다 — git 프로토콜은 HTTP 가 아니라
#     Host 헤더가 없어서 L7 라우팅의 전제가 성립하지 않는다.
#     Harbor 는 인그레스를 타지만 특수하다: host 가 접속 주소일 뿐 아니라 이미지 이름의
#     첫 마디라, 노드 containerd 의 certs.d 디렉토리명과 글자 그대로 같아야 한다(200-harbor).
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

      service = {
        type = "LoadBalancer"

        # ⚠ spec.loadBalancerIP 는 쿠버네티스에서 폐기된 필드라 차트의 loadBalancerIP 대신
        #   MetalLB 어노테이션으로 요청한다. 풀이 autoAssign: false 라서, 이 키에 오타가
        #   나면 조용히 다른 주소가 붙는 것이 아니라 IP 가 아예 배정되지 않아
        #   helm 이 EXTERNAL-IP 를 기다리다 timeout 으로 실패한다(원인이 바로 드러난다).
        annotations = {
          "metallb.io/loadBalancerIPs" = var.ingress_vip
        }

        # 이 저장소의 다른 Service 는 전부 Cluster 인데 여기만 Local 이다(CLAUDE.md 예외).
        # 근거 둘: ① 클라이언트 IP 가 보존된다 ② MetalLB L2 는 ETP Local 일 때 '준비된
        # 엔드포인트가 있는 노드'에서만 VIP 를 광고하므로, 죽은 컨트롤러가 있는 노드로
        # 트래픽이 흘러가는 창이 없다. replica 1 앱에서 Local 이 위험한 것과 상황이 다르다
        # — 여기서 엔드포인트는 아래 antiAffinity 로 노드에 흩어진 컨트롤러 자신이다.
        externalTrafficPolicy = "Local"
      }

      # required 인 이유: 두 replica 가 같은 노드에 뭉치면 그 노드가 죽는 순간 VIP 를
      # 광고할 노드가 사라진다 — 복제본을 둔 목적이 통째로 사라진다. 노드가 3대라
      # 2개를 강제로 흩어도 스케줄이 막히지 않는다(ap 테인트 해제 상태 전제).
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

      # 차트 기본값(cpu 100m)은 이 랩에 과하다 — 노드 CPU 가 2코어뿐이고 nginx 는
      # 랩 트래픽에서 CPU 를 거의 쓰지 않는다. 메모리는 기본값(90Mi)보다 올려 잡는다.
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
      }
    }
  })]

  # ⚠ 없으면 반드시 깨진다. helm 은 LoadBalancer Service 가 EXTERNAL-IP 를 받을 때까지
  #   기다리는데, 풀과 광고가 없으면 그 IP 가 영영 나오지 않아 timeout 에서 실패한다.
  depends_on = [
    kubernetes_manifest.ingress_vip_pool,
    kubernetes_manifest.ingress_vip_l2advertisement,
  ]
}
