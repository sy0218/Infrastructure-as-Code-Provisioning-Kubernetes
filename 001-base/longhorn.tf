# 분산 블록 스토리지 → local-path 와 공존하며 "이름으로 지목해서" 쓴다.
# default 는 local-path 가 유지
# 복제가 필요한 데이터만 storageClassName: longhorn 명시.
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
      # 기본 StorageClass 는 local-path
      defaultClass = false

      # ap 는 control-plane taint 로 스토리지 노드가 s1/s2 둘뿐 → 3 이면 영원히 degraded
      defaultClassReplicaCount = 2
    }
    defaultSettings = {
      # 실제 롱혼 데이터 경로와 일치해야 함 (tfvars 로 주입)
      defaultDataPath = var.longhorn_data_path
    }
  })]
}
