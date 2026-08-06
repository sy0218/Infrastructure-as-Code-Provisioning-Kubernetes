# ===============================================
# [Kubernetes API 접근 권한]
#   → data-layer 의 default SA 에 cluster-admin 을 주는, 저장소 유일의 권한 오브젝트다.
#   → 없으면 prometheus kubernetes_sd 와 data-layer-api 가 403 을 받는데 파드는 정상 기동해 증상이 조용하다.
#   → 대가로 이 네임스페이스의 전 파드가 관리자 권한을 갖는다(배경은 CLAUDE.md '권한 모델').
# ===============================================
resource "kubernetes_cluster_role_binding_v1" "data_layer_default" {
  metadata {
    # ClusterRoleBinding은 클러스터 범위 리소스라 이름이 전역 유일해야 한다.
    name = "${var.namespace}-default-admin"
    labels = {
      "app.kubernetes.io/part-of" = "data-layer"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = var.namespace
    api_group = ""
  }

  # default SA 는 네임스페이스가 생겨야 컨트롤러가 만들어 준다
  depends_on = [kubernetes_namespace_v1.data_layer]
}
