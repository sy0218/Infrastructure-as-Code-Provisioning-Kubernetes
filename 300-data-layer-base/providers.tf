# ===============================================
# [Kubernetes Provider]
#   → 클러스터 접속 수단은 kubeconfig 하나뿐이다(kubeadm control-plane 의 admin.conf 복사본).
#   → typed 리소스만 쓰므로(kubernetes_manifest 없음) 클러스터가 안 닿아도 validate 는 통과한다.
# ===============================================
provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}
