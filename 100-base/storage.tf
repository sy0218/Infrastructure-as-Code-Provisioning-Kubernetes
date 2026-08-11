# ===============================================
# [local-path-provisioner]
#   - K8S 에 Local Path Provisioner를 Helm으로 설치
#   - k8S 기본 스토리지 클래스로 지정하는 테라폼 코드 입니다.
# ===============================================
resource "helm_release" "local_path_provisioner" {
  name             = "local-path-provisioner"
  repository       = "https://charts.containeroo.ch"
  chart            = "local-path-provisioner"
  version          = var.local_path_chart_version
  namespace        = "local-path-storage"
  create_namespace = true

  values = [yamlencode({
    storageClass = {
      defaultClass = true
    }
  })]
}
