# ===============================================
# [TCP Socket Collector]
#   → 장비 push 스트림 → raw.* 토픽. 이 스택에서 유일하게 hostNetwork + nodeSelector 를 쓴다.
#   → 리슨 포트 집합이 런타임에 DB(realtime_source)로 정해져 포트를 '선언'해야 하는 Service 모델과 맞물리지 않는다 → Service 를 만들지 않는다(상세는 매니페스트).
# ===============================================
resource "kubernetes_manifest" "tcp_socket_collector" {
  # 라벨보다 파드가 먼저 뜨면 잠시 Pending 이다 — 자동 복구되지만 순서를 코드로 못 박는다.
  depends_on = [kubernetes_labels.tcp_socket_ingest_node]

  manifest = yamldecode(templatefile("${path.module}/manifests/tcp-socket-collector.yaml.tftpl", {
    namespace = var.namespace
    image     = "${var.harbor_registry}/data-layer/tcp-socket-collector:${var.image_tag}"
    # 변수로 빼지 않는다 — 노드 포트를 직접 잡는 구조라 같은 노드에 2개가 겹치면 bind 실패다
    replicas = 1
    # 한 줄 JSON 관용구(컨슈머 env_block 과 같은 이유). outputs.tf 의 셀렉터 문자열과 출처가 같다.
    node_selector = jsonencode(var.tcp_socket_node_selector)
  }))
}

# ===============================================
# [수집 노드 라벨 — nodeSelector 의 짝]
#   → 원래 kubectl 수동 단계였다: 빠뜨리면 파드가 조용히 Pending, 엉뚱한 노드에 붙으면 Running 인데 장비 트래픽이 안 온다.
#   → 위 nodeSelector 와 같은 변수를 쓰므로 라벨이 어긋날 수 없다. 노드를 옮길 때는 tcp_socket_node_name 만 바꾼다(이전 노드 라벨은 Terraform 이 제거한다).
# ===============================================
resource "kubernetes_labels" "tcp_socket_ingest_node" {
  api_version = "v1"
  kind        = "Node"

  metadata {
    name = var.tcp_socket_node_name
  }

  labels = var.tcp_socket_node_selector

  # kubectl 로 이미 붙어 있는 라벨의 소유권을 넘겨받는다 — 없으면 field manager 충돌로 apply 가 실패한다.
  force = true
}
