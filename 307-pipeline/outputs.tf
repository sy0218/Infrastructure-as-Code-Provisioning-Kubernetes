# ===============================================
# [Terraform Output]
#   → 운영 스크립트/사람이 가져다 쓰는 값만 노출한다.
#   → 조회: terraform -chdir=307-pipeline output -json <이름>
# ===============================================

# DQ 적용이 안 먹을 때 확인 경로:
#   kubectl -n <ns> get pods -l app=cdm-mapper,cdm.mapper/module=<모듈>
#   0건이면 API 가 아니라 라벨/모듈명이 어긋난 것이다.
output "cdm_mapper_deployments" {
  description = "매퍼 모듈 → Deployment 이름 매핑"
  value       = local.cdm_mapper_deployment_names
}

output "cdm_consumer_deployments" {
  description = "컨슈머 종류 → Deployment 이름(= 라벨 app = 컨슈머 그룹 이름)"
  value       = local.cdm_consumer_deployment_names
}

# 라벨 부여는 이 스택이 한다(tcp-socket.tf) — 붙는 노드는 tcp_socket_node_name 이 정한다.
output "tcp_socket_node_selector" {
  description = "TCP 수집기가 뜰 노드를 고르는 라벨(kubectl get nodes -l 에 그대로 쓴다)"
  value       = join(",", [for k, v in var.tcp_socket_node_selector : "${k}=${v}"])
}
