# ===============================================
# [Terraform Output]
#   → 다른 스택/스크립트/사람이 가져다 쓰는 값만 노출한다.
#   → Secret airflow-env 의 값은 절대 내보내지 않는다.
#   → 조회: terraform -chdir=304-airflow output -raw <이름>
# ===============================================

# ⚠ 이 이름은 클라이언트 쪽에서만 해석된다(아래 두 개는 클러스터 내부 주소 — 역할이 다르다).
#   AIRFLOW__API__BASE_URL 및 300-data-layer-base 의 AIRFLOW_UI_URL 과 글자 그대로 같아야 한다.
output "airflow_ui_url" {
  description = "Airflow UI 접속 주소 (호스트명만 — 포트 없음, Ingress 경유)"
  value       = "http://${var.airflow_host}"
}

# FQDN 으로 적어 ndots 검색 낭비를 없앤다
output "airflow_apiserver_service" {
  description = "api-server Service 주소(FQDN:포트) — 클러스터 내부에서 REST 를 부를 때"
  value       = "airflow-apiserver.${var.namespace}.svc.cluster.local:${var.airflow_apiserver_port}"
}

# Secret 의 AIRFLOW__CORE__EXECUTION_API_SERVER_URL 과 같은 local 을 쓴다 — 두 값이 어긋날 수 없다
output "execution_api_server_url" {
  description = "워커(scheduler)가 태스크 상태를 보고하는 Execution API 주소"
  value       = local.execution_api_server_url
}

output "airflow_logs_bucket" {
  description = "태스크 로그가 쌓이는 S3(MinIO) 버킷 — 로컬 MinIO 에 같은 이름의 버킷이 있어야 한다"
  value       = "s3://${var.airflow_logs_bucket}"
}
