# ===============================================
# [KubernetesExecutor — 태스크 파드 원형]
#   → LocalExecutor 시절엔 scheduler 파드가 곧 워커였다. 이제 scheduler 는 파드를 찍기만 하고
#     태스크는 자기 파드에서 돈다 — 태스크 하나가 노드를 물어도 스케줄러가 같이 죽지 않는다.
#   → 권한은 이 스택이 갖지 않는다: 300-data-layer-base 의 ClusterRoleBinding 이 default SA 에
#     cluster-admin 을 줘서 scheduler 가 파드를 만들고 지울 수 있다.
#   → 로그도 추가 작업이 없다. 태스크 파드는 사라지지만 원격 로깅(S3)이 이미 켜져 있어
#     UI 가 MinIO 에서 읽는다.
# ===============================================

locals {
  # 디렉토리째 마운트하므로 파일명이 경로에 붙는다. Secret 의 POD_TEMPLATE_FILE 과
  # scheduler 매니페스트의 mountPath 가 이 한 값에서 갈라져 나온다.
  pod_template_dir  = "/opt/airflow/pod-template"
  pod_template_path = "${local.pod_template_dir}/pod_template.yaml"

  # 렌더 결과를 한 번만 만들어 ConfigMap 과 scheduler 의 checksum 두 곳에서 쓴다.
  pod_template_rendered = templatefile("${path.module}/manifests/pod-template.yaml.tftpl", {
    image         = local.airflow_image
    gitsync_image = local.gitsync_image
    run_as_user   = var.airflow_run_as_user
    fs_group      = var.airflow_fs_group
    git_repo      = var.git_repo
    git_ref       = var.git_ref
  })

  # 원형이 바뀌면 scheduler 를 다시 띄워야 한다 — 파일은 볼륨이라 갱신되지만,
  # 실행 중인 scheduler 프로세스는 기동 시점에 읽은 것을 계속 쓴다.
  pod_template_hash = sha256(local.pod_template_rendered)
}

# ConfigMap 을 typed 리소스로 만드는 이유는 저장소 규칙 그대로다(kubernetes_manifest 는
# 매니페스트 전체를 state 에 남긴다). 여기 담기는 것은 비밀이 아니지만 규칙을 갈라 두지 않는다.
resource "kubernetes_config_map_v1" "airflow_pod_template" {
  metadata {
    name      = "airflow-pod-template"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"    = "airflow"
      "app.kubernetes.io/part-of" = "data-layer"
    }
  }

  # 디렉토리째 마운트하고 파일명을 경로에 붙인다 — subPath 로 꽂으면 ConfigMap 이 바뀌어도
  # 파일이 갱신되지 않는다(그 함정은 git-sync 심볼릭 링크에서 이미 한 번 나왔다).
  data = {
    "pod_template.yaml" = local.pod_template_rendered
  }
}
