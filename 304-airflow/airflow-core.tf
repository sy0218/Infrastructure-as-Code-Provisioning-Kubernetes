# ===============================================
# [Airflow 코어 — apiserver / scheduler / dag-processor / triggerer]
#   → 4개 Deployment 는 이미지·env·실행 UID 가 전부 같고 args 만 다르다.
#   → PVC 도 hostPath 도 없다(코드/DAG 는 이미지에, 로그는 MinIO S3 에) → 남은 상태가 0 이라
#     4개 전부 자유 스케줄된다. 대가는 라이브 로그 — airflow-secret.tf 참조.
#   → 4개 모두 init Job 에 depends_on 한다(airflow-init.tf 참조).
# ===============================================

locals {
  # Secret 이 바뀌면 어노테이션이 바뀌어 4개 Deployment 가 전부 롤아웃된다.
  # envFrom 값은 파드를 다시 만들지 않는 한 갱신되지 않아, 없으면
  # "Secret 은 고쳤는데 동작은 그대로"가 조용히 유지된다.
  # nonsensitive: 해시는 원본을 노출하지 않는다(어노테이션은 평문으로 보인다).
  airflow_env_hash = nonsensitive(sha256(jsonencode(kubernetes_secret_v1.airflow_env.data)))

  # 4개 컴포넌트 공통 템플릿 인자 — 한 곳에서만 고치도록 묶는다.
  # 코드(DAG·커스텀 패키지)는 이미지 안에 있어 이미지 하나가 곧 코드 버전이다 —
  # 파서와 실행 주체가 다른 커밋을 볼 방법이 없다(구 git-sync 시절의 위험이 사라졌다).
  airflow_common_vars = {
    namespace   = var.namespace
    image       = local.airflow_image
    run_as_user = var.airflow_run_as_user
    fs_group    = var.airflow_fs_group
    config_hash = local.airflow_env_hash
  }
}

# api-server — UI/REST 이자 scheduler 가 태스크 상태를 보고하는 Execution API 의 대상
resource "kubernetes_manifest" "airflow_apiserver" {
  manifest = yamldecode(templatefile("${path.module}/manifests/airflow-apiserver-deployment.yaml.tftpl",
    merge(local.airflow_common_vars, {
      replicas       = var.apiserver_replicas
      apiserver_port = var.airflow_apiserver_port
    })
  ))

  depends_on = [kubernetes_manifest.airflow_init_job]
}

# 한 Service 를 두 경로가 함께 쓴다:
#   외부(브라우저)  → Ingress   http://<airflow_host>        (클라이언트 hosts → VIP)
#   내부(scheduler) → ClusterIP http://airflow-apiserver:<airflow_apiserver_port>/execution/  (CoreDNS)
resource "kubernetes_manifest" "airflow_apiserver_service" {
  manifest = yamldecode(templatefile("${path.module}/manifests/airflow-apiserver-service.yaml.tftpl", {
    namespace      = var.namespace
    apiserver_port = var.airflow_apiserver_port
  }))
}

# 브라우저 진입점 — Host 가 AIRFLOW__API__BASE_URL 과 어긋나면 로그인 직후 리다이렉트가 깨진다
resource "kubernetes_manifest" "airflow_apiserver_ingress" {
  manifest = yamldecode(templatefile("${path.module}/manifests/airflow-apiserver-ingress.yaml.tftpl", {
    namespace      = var.namespace
    host           = var.airflow_host
    apiserver_port = var.airflow_apiserver_port
  }))

  # 백엔드가 없는 Ingress 는 502 를 돌려준다(오브젝트 생성 자체는 성공해서 더 헷갈린다)
  depends_on = [kubernetes_manifest.airflow_apiserver_service]
}

# scheduler — KubernetesExecutor 라 태스크를 직접 돌리지 않고 태스크 파드를 찍는다.
# 그래서 이 파드만 태스크 파드 원형(ConfigMap)을 마운트한다.
resource "kubernetes_manifest" "airflow_scheduler" {
  manifest = yamldecode(templatefile("${path.module}/manifests/airflow-scheduler-deployment.yaml.tftpl",
    merge(local.airflow_common_vars, {
      replicas          = var.scheduler_replicas
      pod_template_dir  = local.pod_template_dir
      pod_template_hash = local.pod_template_hash
    })
  ))

  # 원형이 없으면 파드가 CreateContainerConfigError 로 멈춘다(마운트 대상 부재)
  depends_on = [
    kubernetes_manifest.airflow_init_job,
    kubernetes_config_map_v1.airflow_pod_template,
  ]
}

# dag-processor — Airflow 3 에서 DAG 파싱이 분리된 컴포넌트.
# 파싱 사고(무한 루프·메모리)가 스케줄링 루프를 멈추지 않게 하는 것이 분리의 목적이다.
resource "kubernetes_manifest" "airflow_dag_processor" {
  manifest = yamldecode(templatefile("${path.module}/manifests/airflow-dag-processor-deployment.yaml.tftpl",
    merge(local.airflow_common_vars, { replicas = var.dag_processor_replicas })
  ))

  depends_on = [kubernetes_manifest.airflow_init_job]
}

# triggerer — deferrable 오퍼레이터용(현재 DAG 엔 없지만 Airflow 3 표준 구성)
resource "kubernetes_manifest" "airflow_triggerer" {
  manifest = yamldecode(templatefile("${path.module}/manifests/airflow-triggerer-deployment.yaml.tftpl",
    merge(local.airflow_common_vars, { replicas = var.triggerer_replicas })
  ))

  depends_on = [kubernetes_manifest.airflow_init_job]
}
