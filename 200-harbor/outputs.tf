# ===============================================
# [Terraform Output]
#   → 다른 스택과 이미지 빌드 스크립트가 가져다 쓰는 접속 주소.
#   → 조회: terraform output / terraform output -raw <이름>
# ===============================================

output "harbor_url" {
  description = "Harbor UI/API 접속 주소 (포트 없음 — Ingress 경유)"
  value       = "http://${var.harbor_host}"
}

# ⚠ 이 값은 '주소'가 아니라 이미지 이름의 첫 마디다 — 전 스택 tfvars 의 harbor_registry,
#   노드 3대의 certs.d/<이 값>/hosts.toml 디렉토리명과 글자 그대로 같아야 한다.
output "harbor_registry" {
  description = "docker tag/push 에 붙이는 레지스트리 주소 (스킴 없음)"
  value       = var.harbor_host
}

# 최종 이미지 형식: <registry>/<project>/<image>:<tag>
output "harbor_image_prefix" {
  description = "data-layer 이미지 주소 접두어 (프로젝트까지 포함)"
  value       = "${var.harbor_host}/${harbor_project.data_layer.name}"
}
