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
    # [ Helm Provider]
    # → Kubernetes에 Harobor Helm Chart 설치
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }

    # [ Harbor Provider ]
    # → Harbor API를 통해 프로젝트 설정
    harbor = {
      source  = "registry.terraform.io/goharbor/harbor"
      version = "3.10.21"
    }
  }
}
