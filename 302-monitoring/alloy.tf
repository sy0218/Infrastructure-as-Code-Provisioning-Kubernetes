# ===============================================
# [Alloy DaemonSet]
#   → 노드별 서버/컨테이너 메트릭 노출 에이전트. "노드당 1개"가 곧 사양이라 DaemonSet 이다.
#   → Prometheus 가 라벨(app=alloy)로 발견하므로 노드가 늘어도 고칠 파일이 없다.
# ===============================================

locals {
  # 렌더 결과를 한 번만 만들어 ConfigMap 과 파드 템플릿의 checksum 두 곳에서 쓴다.
  # templatefile 을 두 번 호출하면 인자 한쪽만 고쳤을 때 "롤아웃은 됐는데 설정은 그대로"가 된다.
  alloy_config_rendered = templatefile("${path.module}/manifests/alloy-config.yaml.tftpl", {
    namespace = var.namespace
  })
}

# 수집 설정의 소유자는 이미지가 아니라 이 ConfigMap 이다 — alloy 이미지는 FROM 한 줄이라
# 수집 항목을 바꾸는 데 재빌드도, 새 태그도 필요 없다(apply 만으로 롤아웃된다).
# typed 가 아니라 kubernetes_manifest 인 이유는 prometheus-config 와 같다: 시크릿이 없고,
# River 설정의 들여쓰기가 파일에서 눈에 보여야 한다.
resource "kubernetes_manifest" "alloy_config" {
  manifest = yamldecode(local.alloy_config_rendered)
}

resource "kubernetes_manifest" "alloy_daemonset" {
  manifest = yamldecode(templatefile("${path.module}/manifests/alloy-daemonset.yaml.tftpl", {
    namespace  = var.namespace
    image      = "${var.harbor_registry}/data-layer/alloy:${var.image_tag}"
    alloy_port = var.alloy_port

    # readinessProbe 경로 = Prometheus 의 metrics_path. 어긋나면 "Ready 인데 스크랩 404"가
    # 되므로 같은 변수에서 뽑는다.
    node_metrics_path = var.alloy_node_metrics_path

    # 설정이 바뀌면 이 해시가 바뀌어 파드가 스스로 롤아웃된다
    config_hash = sha256(local.alloy_config_rendered)
  }))

  # ConfigMap 이 없으면 파드가 볼륨 마운트 실패로 ContainerCreating 에서 멈춘다.
  depends_on = [
    kubernetes_manifest.alloy_config,
  ]
}
