# ===============================================
# [Longhorn — 이름으로 지목해 쓰는 복제 스토리지]
#   → 자체 복제가 없는 단일 인스턴스(Harbor·Prometheus·Grafana)만 storageClassName: longhorn 을 명시한다.
#   → 노드 선행작업(open-iscsi/multipath/데이터 경로)은 Ansible longhorn_prereq 롤 담당 — Terraform 밖 수동 단계다.
# ===============================================
resource "helm_release" "longhorn" {
  name             = "longhorn"
  repository       = "https://charts.longhorn.io"
  chart            = "longhorn"
  version          = var.longhorn_chart_version
  namespace        = "longhorn-system"
  create_namespace = true
  timeout          = 600 # manager/driver/UI 등 컴포넌트가 많아 첫 기동이 느리다

  values = [yamlencode({
    persistence = {
      # 기본 스토리지 클래스는 local-path 가 유지한다
      defaultClass = false

      # ap 는 control-plane taint 라 스토리지 노드가 s1/s2 둘뿐 → 3 이면 영원히 degraded
      defaultClassReplicaCount = 2
    }
    defaultSettings = {
      # 노드의 실제 디스크 마운트 경로와 일치해야 한다 (tfvars 주입)
      defaultDataPath = var.longhorn_data_path
    }
  })]
}
