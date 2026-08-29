# ===============================================
# [MetalLB VIP 설정]
#
# MetalLB가 외부에서 사용할 VIP를 관리하도록 설정한다.
#
# IPAddressPool       → 사용할 VIP 주소를 등록한다.
# L2Advertisement     → 등록한 VIP를 네트워크에 ARP로 광고한다.
#
# ingress-nginx용 VIP와 PostgreSQL용 VIP를
# 각각 별도의 Pool로 관리한다.
# ===============================================

locals {
  # ingress-nginx가 사용할 VIP Pool 이름
  ip_pool_name = "ingress-vip"

  # PostgreSQL 외부 접속에 사용할 VIP Pool 이름
  postgres_pool_name = "postgres-vip"
}


# -----------------------------------------------
# [Ingress VIP 등록]
# -----------------------------------------------
# → MetalLB에게 ingress-nginx가 사용할 VIP를 알려준다.
resource "kubernetes_manifest" "ingress_vip_pool" {
  manifest = yamldecode(templatefile("${path.module}/manifests/ipaddresspool.yaml.tftpl", {
    metallb_namespace = var.metallb_namespace
    pool_name         = local.ip_pool_name
    vip               = var.ingress_vip
  }))
}

# -----------------------------------------------
# [Ingress VIP 네트워크 광고]
# -----------------------------------------------
# → 등록한 VIP를 L2(ARP) 방식으로 네트워크에 광고한다.
# → MetalLB가 현재 VIP를 가진 노드의 네트워크 인터페이스에서
#   해당 VIP에 대한 ARP 응답을 하도록 만든다.
resource "kubernetes_manifest" "ingress_vip_l2advertisement" {
  manifest = yamldecode(templatefile("${path.module}/manifests/l2advertisement.yaml.tftpl", {
    metallb_namespace = var.metallb_namespace
    pool_name         = local.ip_pool_name
  }))

  # VIP Pool을 먼저 만든 다음 광고 설정을 적용한다.
  depends_on = [kubernetes_manifest.ingress_vip_pool]
}

# -----------------------------------------------
# [PostgreSQL 외부 접속 VIP]
# -----------------------------------------------
#
# PostgreSQL은 HTTP/HTTPS가 아닌 TCP 서비스이므로
# Ingress를 거치지 않고 전용 VIP로 직접 접속한다.
#
# 외부 클라이언트 → PostgreSQL VIP:5432
#
# NodePort 대신 LoadBalancer(VIP)를 사용해
# 표준 PostgreSQL 포트 5432로 접속할 수 있도록 한다.
#
# 303-postgres의 External Service가
# 이 VIP Pool에서 IP를 요청한다.
# -----------------------------------------------

resource "kubernetes_manifest" "postgres_vip_pool" {
  manifest = yamldecode(templatefile("${path.module}/manifests/ipaddresspool.yaml.tftpl", {
    metallb_namespace = var.metallb_namespace
    pool_name         = local.postgres_pool_name
    vip               = var.postgres_vip
  }))
}

# -----------------------------------------------
# [PostgreSQL VIP 네트워크 광고]
# -----------------------------------------------
# PostgreSQL VIP도 L2(ARP) 방식으로 네트워크에 광고한다.

resource "kubernetes_manifest" "postgres_vip_l2advertisement" {
  manifest = yamldecode(templatefile("${path.module}/manifests/l2advertisement.yaml.tftpl", {
    metallb_namespace = var.metallb_namespace
    pool_name         = local.postgres_pool_name
  }))

  # PostgreSQL VIP Pool 생성 후 광고 설정을 적용한다.
  depends_on = [kubernetes_manifest.postgres_vip_pool]
}