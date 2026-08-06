# ===============================================
# [Terraform Output]
#   → 이 스택의 공개 인터페이스. 네임스페이스·공용 ConfigMap/Secret 이름은
#     여기가 아니라 300-data-layer-base 의 output 에서 가져간다.
# ===============================================

output "schema_registry_url" {
  description = "Schema Registry 주소 (클러스터 내부 Service DNS)"
  value       = local.schema_registry_url
}

# ⚠ 전제: 접속하는 PC 가 kafka_ui_host 를 인그레스 VIP 로 풀 수 있어야 한다(hosts 또는 DNS).
output "kafka_ui_url" {
  description = "Kafka UI 접속 주소 (http://<kafka_ui_host> — 포트 없음, Ingress 경유)"
  value       = local.kafka_ui_url
}
