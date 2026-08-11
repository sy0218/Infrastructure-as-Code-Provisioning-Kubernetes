# ===============================================
# [Terraform / Provider 버전]
#   → 전부 정확히 고정한다 
#   → 범위 연산자(>=, ~>) 금지.
#   → 업그레이드는 버전 숫자를 고치는 커밋으로만 한다.
# ===============================================
terraform {
  required_version = "1.15.8"

  required_providers {
    # Harbor 차트 배포
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }

    # Harbor API (프로젝트 등)
    harbor = {
      source  = "registry.terraform.io/goharbor/harbor"
      version = "3.10.21"
    }
  }
}
