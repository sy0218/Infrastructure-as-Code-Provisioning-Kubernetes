# ===============================================
# [Providers.tf]
#   - Terraform이 외부 시스템을 제어하기 위한 연결 설정이다.
#
# Helm Provider   → Kubernetes에 Helm Chart 설치 및 관리
# Harbor Provider → Harbor REST API를 통한 프로젝트 등 관리
#
# → Helm은 kubeconfig를 통해 대상 Kubernetes 클러스터에 접속한다.
# → Harbor는 REST API를 통해 Harbor 서버에 접속한다.
# ===============================================

provider "helm" {
  kubernetes = {
    config_path = pathexpand(var.kubeconfig_path)
  }
}

provider "harbor" {
  url      = "http://${var.harbor_host}"
  username = "admin"
  password = var.harbor_admin_password
}