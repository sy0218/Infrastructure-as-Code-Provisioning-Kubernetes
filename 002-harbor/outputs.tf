# 이 스택의 공개 인터페이스 — 다른 스택/스크립트/사람이 가져다 쓰는 값만 노출
# 조회: terraform output / 스크립트에서: terraform output -raw harbor_registry
output "harbor_url" {
  description = "Harbor UI/API 접속 주소"
  value       = "http://${var.harbor_external_ip}:${var.harbor_nodeport}"
}

output "harbor_registry" {
  description = "docker tag/push 에 붙이는 레지스트리 주소 (스킴 없음)"
  value       = "${var.harbor_external_ip}:${var.harbor_nodeport}"
}
