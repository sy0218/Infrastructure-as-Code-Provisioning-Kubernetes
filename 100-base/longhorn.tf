# ===============================================
# [Longhorn]
# ===============================================
# - Kubernetes에서 사용할 분산 스토리지 Longhorn을 설치합니다.
# - Longhorn은 여러 노드에 데이터를 복제
#   → 특정 노드에 장애 발생해도 데이터 유지 가능
#
# [주의]
# - Longhorn 설치 전에 필요한 노드 설정은
# → Ansible의 longhorn_prereq Role에서 미리 준비합니다.
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
      defaultClass             = false
      defaultClassReplicaCount = var.longhorn_replica_count
    }
    defaultSettings = {
      # 노드의 실제 디스크 마운트 경로와 일치해야 한다 (tfvars 주입)
      defaultDataPath = var.longhorn_data_path
    }
  })]
}
