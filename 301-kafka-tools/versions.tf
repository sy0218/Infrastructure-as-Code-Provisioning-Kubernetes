# ===============================================
# [Terraform / Provider 버전]
#   → 전부 정확히 고정한다. 범위 연산자(>=, ~>) 금지 — 업그레이드는 숫자를 고치는 커밋으로만.
#   → 서드파티 차트를 쓰지 않고 매니페스트를 직접 쓰므로 helm 프로바이더가 없다.
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
