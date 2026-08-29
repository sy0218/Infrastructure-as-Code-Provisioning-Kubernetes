# ===============================================
# [Helm Provider]
#   - 테라폼이 Helm을 통해 k8s에 접근할 때 사용할 설정입니다.
#   - kubernetes 접속 정보는 kubeconfig 파일 하나로 관리합니다.
# ===============================================
provider "helm" {
  kubernetes = {
    config_path = pathexpand(var.kubeconfig_path)
  }
}
