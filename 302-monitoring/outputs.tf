# ===============================================
# [Terraform Output]
#   → 다른 스택/스크립트/사람이 가져다 쓰는 값만 노출한다.
#   → 내부 Service 주소(서버 간 호출)와 외부 Ingress 주소(브라우저)는 역할이 다르니 섞지 말 것.
# ===============================================

output "prometheus_url" {
  description = "Prometheus 질의 엔드포인트(클러스터 내부)"
  value       = "http://prometheus.${var.namespace}.svc.cluster.local:${var.prometheus_port}"
}

output "grafana_service_url" {
  description = "Grafana 클러스터 내부 주소 (서버 간 호출용)"
  value       = "http://grafana.${var.namespace}.svc.cluster.local:${var.grafana_port}"
}

output "grafana_external_url" {
  description = "Grafana 외부 접속 주소 (브라우저/iframe — 포트 없음, Ingress 경유)"
  value       = "http://${var.grafana_host}"
}

output "prometheus_external_url" {
  description = "Prometheus 디버깅 UI 외부 주소 (무인증 — 내부망 전제)"
  value       = "http://${var.prometheus_host}"
}
