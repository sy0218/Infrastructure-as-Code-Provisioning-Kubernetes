# ===============================================
# [Terraform Output]
#   → 다른 스택/스크립트/사람이 가져다 쓰는 값만 노출한다.
#   → 조회: terraform -chdir=306-cdc output -raw <이름>
# ===============================================

# ⚠ 300-data-layer-base 의 공용 ConfigMap 키 KAFKA_CONNECT_URL 과 반드시 같아야 한다(양쪽이 계약)
output "kafka_connect_url" {
  description = "Connect REST 주소 (관리 화면이 커넥터를 등록/삭제할 때 쓴다)"
  value       = "http://cdc-connect.${var.namespace}.svc.cluster.local:${var.connect_rest_port}"
}

output "connect_internal_topics" {
  description = "Connect 의 유일한 상태 저장소(내부 토픽 3종) — 백업/이관 대상"
  value = {
    config = var.connect_config_storage_topic
    offset = var.connect_offset_storage_topic
    status = var.connect_status_storage_topic
  }
}
