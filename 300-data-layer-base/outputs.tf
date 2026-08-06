# ===============================================
# [Terraform Output]
#   → 조회: terraform output -raw <이름>
#   → 전부 사람이 값을 확인하는 용도다. 301 은 이 output 이 아니라 공용 ConfigMap 을 data 소스로 직접 읽는다.
# ===============================================

output "namespace" {
  description = "data-layer Kubernetes Namespace 이름"
  value       = kubernetes_namespace_v1.data_layer.metadata[0].name
}

output "kafka_bootstrap" {
  description = "Kafka bootstrap server 주소"
  value       = var.kafka_bootstrap_servers
}

output "kafka_bootstrap_plaintext" {
  description = "Schema Registry 용 PLAINTEXT:// 접두어 형태 (ConfigMap KAFKA_BOOTSTRAP_PLAINTEXT 와 같은 값)"
  value       = local.kafka_bootstrap_plaintext
}

output "schema_registry_url" {
  description = "Schema Registry 접속 주소"
  value       = local.schema_registry_url
}

output "common_config_map" {
  description = "공통 ConfigMap 이름 (envFrom.configMapRef 사용)"
  value       = kubernetes_config_map_v1.data_layer_env.metadata[0].name
}

output "common_secret" {
  description = "공통 Secret 이름 (envFrom.secretRef 사용)"
  value       = kubernetes_secret_v1.data_layer_secrets.metadata[0].name
}
