# ===============================================
# [Terraform Output]
#   → 조회: terraform -chdir=303-git output -raw <이름>
# ===============================================

# ⚠ 304-airflow 의 tfvars `git_repo` 와 반드시 같아야 한다(양쪽이 계약).
output "git_repo_url" {
  description = "클러스터 안에서 clone 할 주소 — git-sync 가 쓰는 값"
  value       = local.repo_url_internal
}

# 짧은 이름을 쓰지 않는 이유는 내부 주소와 같다 — 여기는 반대로 PC 의 hosts 가 푼다
output "git_push_url" {
  description = "로컬 PC 에서 push 할 주소 (git remote add origin <이 값>)"
  value       = local.repo_url_external
}
