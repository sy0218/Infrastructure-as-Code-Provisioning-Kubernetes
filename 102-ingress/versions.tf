# ===============================================
# [Terraform / Provider 버전]
#   → 전부 정확 고정 — 범위 연산자(>=, ~>) 금지.
#   ⚠ 이 스택은 101-metallb 가 apply 돼 있어야 plan 이 통과한다. kubernetes_manifest 는
#     plan 시점에 API 서버에 리소스 타입을 물어보는데, IPAddressPool/L2Advertisement 는
#     MetalLB 차트가 설치하는 CRD 라서 그 전에는 타입 자체가 존재하지 않는다
#     ("300 이 apply 돼 있어야 301 plan 이 통과한다" 와 같은 제약이다).
# ===============================================
terraform {
  required_version = "1.15.8"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
  }
}
