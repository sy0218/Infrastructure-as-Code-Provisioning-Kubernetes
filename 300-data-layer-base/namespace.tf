# ===============================================
# [네임스페이스 — data-layer]
#   → 이 스택이 유일한 소유자다. 301~307 은 이름으로 참조만 한다.
#   → 두 state 가 같은 오브젝트를 가지면 한쪽 destroy 가 다른 쪽까지 지운다.
# ===============================================
resource "kubernetes_namespace_v1" "data_layer" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/part-of" = "data-layer"
    }
  }
}
