# ===============================================
# [Helm Provider]
#   → 클러스터 접속은 kubeconfig 하나로 일원화한다(kubeadm control-plane 의 admin.conf 복사본).
# ===============================================
provider "helm" {
  kubernetes = {
    config_path = pathexpand(var.kubeconfig_path)
  }
}

# ===============================================
# [Harbor Provider]
#   → Harbor REST API 로 프로젝트를 관리한다.
#   → URL 은 helm_release 의 externalURL 과 같은 주소여야 하고, Harbor 가 뜬 뒤에야 응답한다
#     (첫 apply 는 순서상 helm → project).
# ===============================================
provider "harbor" {
  url      = "http://${var.harbor_host}"
  username = "admin"
  password = var.harbor_admin_password
}
