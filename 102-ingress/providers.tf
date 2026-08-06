# ===============================================
# [Provider]
#   → 클러스터 접속은 kubeconfig 하나로 일원화한다.
#   → 프로바이더가 둘인 이유: VIP 대역은 MetalLB 의 CR(kubernetes)이고
#     컨트롤러는 서드파티 차트(helm)다.
# ===============================================
provider "helm" {
  kubernetes = {
    config_path = pathexpand(var.kubeconfig_path)
  }
}

provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}
