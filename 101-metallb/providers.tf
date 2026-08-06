# ===============================================
# [Helm Provider]
#   → 클러스터 접속은 kubeconfig 하나로 일원화한다(kubeadm control-plane 의 admin.conf 복사본).
# ===============================================
provider "helm" {
  kubernetes = {
    config_path = pathexpand(var.kubeconfig_path)
  }
}
