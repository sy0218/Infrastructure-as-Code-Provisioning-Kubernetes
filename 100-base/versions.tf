# ===============================================
# [Terraform / Provider 버전]
#   - 전부 정확 고정 → 범위 연산자(>=, ~>) 금지.
#   - 업그레이드는 버전 숫자를 고치는 커밋으로만 한다.
# ===============================================
terraform {
  required_version = "1.15.8"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
  }
}
