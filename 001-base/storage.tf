# 동적 스토리지 프로비저너 — kubeadm 클러스터엔 기본 StorageClass 가 없어서
# PVC(Harbor registry/db, 이후 모니터링 스택의 TSDB 등)가 바인딩되지 못한다.
# 노드 로컬 디스크(/opt/local-path-provisioner)에 PV 를 만들어 주는 방식.
# 클러스터 공용 기반이므로 어떤 앱 스택보다 먼저(001) 적용한다.
resource "helm_release" "local_path_provisioner" {
  name             = "local-path-provisioner"
  repository       = "https://charts.containeroo.ch"
  chart            = "local-path-provisioner"
  version          = var.local_path_chart_version
  namespace        = "local-path-storage"
  create_namespace = true

  values = [yamlencode({
    storageClass = {
      # storageClassName 을 명시하지 않은 PVC 도 local-path 로 바인딩
      defaultClass = true
    }
  })]
}
