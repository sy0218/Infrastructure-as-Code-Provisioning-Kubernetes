# ===============================================
# [MetalLB VIP 설정]
#
# → ingress-nginx가 사용할 VIP 주소를 MetalLB에 등록한다.
# → IPAddressPool : "이 VIP를 사용할 수 있다"라고 등록
# → L2Advertisement : "이 VIP를 네트워크에 광고"하도록 설정
#
# → 101-metallb는 MetalLB 기능(CRD/Controller)을 설치한다.
# → 이 스택은 실제로 사용할 VIP 주소와 광고 설정을 관리한다.
# ===============================================

locals {

  # IPAddressPool과 L2Advertisement가 같은 Pool을 사용하도록 이름을 한 곳에서 관리한다.
  ip_pool_name = "ingress-vip"
}

# ===============================================
# [VIP 주소 등록]
# ===============================================

# → MetalLB에게 ingress-nginx가 사용할 VIP를 알려준다.
# → 예: 192.168.56.240
resource "kubernetes_manifest" "ingress_vip_pool" {
  manifest = yamldecode(templatefile("${path.module}/manifests/ipaddresspool.yaml.tftpl", {
    metallb_namespace = var.metallb_namespace
    pool_name         = local.ip_pool_name
    vip               = var.ingress_vip
  }))
}

# ===============================================
# [VIP L2 광고]
# ===============================================

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