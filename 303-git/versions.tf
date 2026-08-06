# ===============================================
# [Terraform / Provider 버전]
#   → 전부 정확 고정. 범위 연산자(>=, ~>) 금지 — 업그레이드는 숫자를 고치는 커밋으로만.
#   → 차트를 쓰지 않는 스택이라 helm 프로바이더를 선언하지 않는다.
# ===============================================
terraform {
  required_version = "1.15.8"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
  }
}
