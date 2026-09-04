# ===============================================
# [Longhorn]
# ===============================================
# - Kubernetes 분산 스토리지 설치
# - 노드 간 볼륨 복제로 노드 장애 대응
#
# [주의]
# - 설치 전 필수 노드 설정은
#   Ansible longhorn_prereq Role에서 준비
# ===============================================
resource "helm_release" "longhorn" {
  name             = "longhorn"
  repository       = "https://charts.longhorn.io"
  chart            = "longhorn"
  version          = var.longhorn_chart_version
  namespace        = "longhorn-system"
  create_namespace = true
  timeout          = 600 # 초기 컴포넌트 기동 시간 고려

  values = [yamlencode({
    persistence = {
      # local-path를 기본 StorageClass로 유지
      defaultClass             = false
      defaultClassReplicaCount = var.longhorn_replica_count
    }

    defaultSettings = {
      # Longhorn 데이터 디렉터리
      defaultDataPath = var.longhorn_data_path

      # 노드 장애 시 볼륨 사용 파드를 다른 노드로 재배치
      nodeDownPodDeletionPolicy = "delete-both-statefulset-and-deployment-pod"
    }
  })]
}