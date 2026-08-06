# ===============================================
# [Terraform Output]
#   → 조회: terraform -chdir=101-metallb output -raw <이름>
# ===============================================

# 102-ingress 의 metallb_namespace 미러 선언이 가리키는 원본이다.
# MetalLB 는 자기 네임스페이스의 CR 만 읽으므로 IPAddressPool 도 이 값 안에 들어가야 한다.
output "metallb_namespace" {
  description = "MetalLB 네임스페이스 — IPAddressPool/L2Advertisement 를 두어야 하는 곳"
  value       = var.namespace
}
