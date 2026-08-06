# ===============================================
# [VIP 대역과 광고 방식]
#   → 101-metallb 는 '기능'을, 이 파일은 '주소'를 소유한다. 스택이 갈린 것은 취향이
#     아니라 제약이다 — CRD 를 설치하는 apply 와 그 CRD 를 쓰는 plan 이 같은 스택에
#     있으면 첫 plan 이 타입을 못 찾고 죽는다(versions.tf 배너).
# ===============================================

locals {
  # 두 CR 이 같은 이름을 가리켜야 광고가 붙는다 — 오타로 갈라지지 않도록 한 곳에서 만든다
  ip_pool_name = "ingress-vip"
}

resource "kubernetes_manifest" "ingress_vip_pool" {
  manifest = yamldecode(templatefile("${path.module}/manifests/ipaddresspool.yaml.tftpl", {
    metallb_namespace = var.metallb_namespace
    pool_name         = local.ip_pool_name
    vip               = var.ingress_vip
  }))
}

resource "kubernetes_manifest" "ingress_vip_l2advertisement" {
  manifest = yamldecode(templatefile("${path.module}/manifests/l2advertisement.yaml.tftpl", {
    metallb_namespace = var.metallb_namespace
    pool_name         = local.ip_pool_name
  }))

  # 광고 대상이 먼저 있어야 한다(없는 풀을 가리키는 광고는 아무 일도 하지 않는다)
  depends_on = [kubernetes_manifest.ingress_vip_pool]
}
