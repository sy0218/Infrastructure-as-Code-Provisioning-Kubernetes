# 클러스터 접속은 kubeconfig 하나로 일원화 → kubeadm 컨트롤 노드의 admin.conf 복사본 기준
provider "helm" {
  kubernetes = {
    config_path = pathexpand(var.kubeconfig_path)
  }
}
