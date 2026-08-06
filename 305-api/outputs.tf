# ===============================================
# [Terraform Output]
#   → 다른 스택·스크립트·사람이 가져다 쓰는 값만 노출한다.
#   → 조회: terraform -chdir=305-api output -raw <이름>
# ===============================================

output "api_url" {
  description = "관리 화면 접속 주소 (호스트명만 — 포트 없음, Ingress 경유)"
  value       = "http://${var.api_host}"
}

# 같은 프로세스의 REST 진입점 — "/" 화면과 달리 인증이 걸린다
output "api_rest_url" {
  description = "REST API 접속 주소 (X-API-Key 헤더 필요)"
  value       = "http://${var.api_host}/api"
}

# 짧은 이름은 ndots:5 탓에 search 도메인을 순회하는 실패 질의가 먼저 나간다 → FQDN 으로 적는다
output "api_service_endpoint" {
  description = "클러스터 내부에서 API 를 부를 주소 (FQDN:포트 — 브라우저용 외부 주소가 아니다)"
  value       = "data-layer-api.${var.namespace}.svc.cluster.local:${var.api_port}"
}
