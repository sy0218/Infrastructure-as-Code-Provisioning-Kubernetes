# ===============================================
# [ versions.tf ] 
#   - Terraform / Provider 버전
#   - 전부 정확 고정 → 범위 연산자(>=, ~>) 금지.
#
# 테라폼 프로젝트에서 → 어떤 테라폼과 프로바이더를 사용할지 명시
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
