# ===============================================
# [Providers.tf]
#   - Terraform이 외부 시스템을 제어하기 위한 연결 설정이다.
#
# Kubernetes Provider → Kubernetes 리소스 관리
# Helm Provider       → Helm Chart 설치 및 관리
#
# → kubeconfig를 통해 대상 Kubernetes 클러스터에 접속한다.
# ===============================================
provider "helm" {
  kubernetes = {
    config_path = pathexpand(var.kubeconfig_path)
  }
}

provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}
