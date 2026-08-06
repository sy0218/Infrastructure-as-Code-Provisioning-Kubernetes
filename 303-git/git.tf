# ===============================================
# [data-layer-git — 저장소 서버]
#   → 304-airflow 의 git-sync 가 여기서 DAG·커스텀 패키지를 받아 간다.
#     그래서 이 스택이 304 보다 앞 번호다 — 저장소가 없으면 airflow 파드의 init 이 실패한다.
#   → 노드 로컬(s2) bare 저장소 대신 클러스터에 둔 이유 둘:
#       ① 노드가 죽어도 볼륨이 따라가 저장소가 살아남는다.
#       ② 파드가 Service FQDN 으로 붙을 수 있다 — 노드 호스트명은 CoreDNS 가 못 푼다.
# ===============================================

locals {
  git_image = "${var.harbor_registry}/data-layer/git:${var.image_tag}"

  # 이 두 주소가 이 스택의 계약이다. 안쪽은 304-airflow 의 git_repo 와,
  # 바깥쪽은 사람이 치는 `git remote add` 와 글자가 같아야 한다.
  repo_url_internal = "git://data-layer-git.${var.namespace}.svc.cluster.local:${var.git_daemon_port}/${var.git_repo_name}.git"
  repo_url_external = "git://${var.git_host}:${var.git_nodeport}/${var.git_repo_name}.git"
}

resource "kubernetes_manifest" "git_pvc" {
  manifest = yamldecode(templatefile("${path.module}/manifests/git-pvc.yaml.tftpl", {
    namespace     = var.namespace
    storage_size  = var.git_storage_size
    storage_class = var.git_storage_class
  }))
}

resource "kubernetes_manifest" "git_deployment" {
  manifest = yamldecode(templatefile("${path.module}/manifests/git-deployment.yaml.tftpl", {
    namespace   = var.namespace
    image       = local.git_image
    daemon_port = var.git_daemon_port
    repo_name   = var.git_repo_name
  }))

  # PVC 가 없으면 파드가 볼륨 마운트 단계에서 멈춘다
  depends_on = [kubernetes_manifest.git_pvc]
}

resource "kubernetes_manifest" "git_service" {
  manifest = yamldecode(templatefile("${path.module}/manifests/git-service.yaml.tftpl", {
    namespace   = var.namespace
    daemon_port = var.git_daemon_port
    nodeport    = var.git_nodeport
  }))
}
