# ===============================================
# [Terraform / Provider 버전]
#   → 전부 정확 고정
#   → 범위 연산자(>=, ~>) 금지.
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
