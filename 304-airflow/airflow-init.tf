# ===============================================
# [Airflow 초기화 Job — db migrate + 관리자 계정]
#   → initContainer 가 아니라 별도 Job 인 이유: 마이그레이션은 '클러스터에 한 번'인데
#     컴포넌트는 4개다. initContainer 면 같은 마이그레이션이 4번 동시에 돌아 alembic 이 락을 잡는다.
#   → 그래서 airflow-core.tf 의 4개 Deployment 가 전부 이 Job 에 depends_on 한다 —
#     메타DB 스키마가 없으면 기동 중 에러로 죽는다.
# ===============================================

locals {
  # 이미지 태그에는 K8s 이름 규칙이 허용하지 않는 문자(대문자·'_'·'+')가 들어올 수 있다
  # → Job 이름용으로 DNS-1123 라벨 형태로 좁힌다.
  image_tag_slug = lower(replace(var.image_tag, "/[^a-zA-Z0-9]+/", "-"))

  airflow_image = "${var.harbor_registry}/data-layer/airflow:${var.image_tag}"
}

resource "kubernetes_manifest" "airflow_init_job" {
  manifest = yamldecode(templatefile("${path.module}/manifests/airflow-init-job.yaml.tftpl", {
    namespace   = var.namespace
    job_name    = "airflow-init-${local.image_tag_slug}"
    image       = local.airflow_image
    run_as_user = var.airflow_run_as_user
    fs_group    = var.airflow_fs_group
  }))

  # ⚠ Job 컨트롤러가 파드 템플릿에 라벨 4종(controller-uid·job-name 및 batch.kubernetes.io/ 접두)을
  #   생성 시점에 붙인다 — UUID 라서 매니페스트에 미리 적을 수 없고, 그대로 두면 apply 가
  #   "unexpected new value: new element ... has appeared" 로 실패한다.
  #   computed_fields 는 '서버가 채우는 자리'라고 알려주는 장치다(기본값 2개를 덮어쓰므로 같이 적는다).
  computed_fields = [
    "metadata.annotations",
    "metadata.labels",
    "spec.template.metadata.labels",
  ]

  # Secret 이 없으면 파드가 CreateContainerConfigError 로 멈춘다(envFrom 대상 부재)
  depends_on = [kubernetes_secret_v1.airflow_env]
}
