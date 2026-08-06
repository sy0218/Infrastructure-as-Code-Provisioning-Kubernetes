# ===============================================
# [local-path-provisioner — 기본 StorageClass]
#   → kubeadm 엔 기본 StorageClass 가 없어 storageClassName 을 적지 않은 PVC 는 전부 Pending 이다.
#   → PV 는 파드가 뜬 노드의 로컬 디스크(/opt/local-path-provisioner)에 만들어진다 → 볼륨이 노드에 묶인다.
#   ⚠ 안전망일 뿐이다. 실제로 여기 떨어진 PVC 가 하나 있다(harbor 의 trivy 캐시) — 200-harbor 참조.
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
