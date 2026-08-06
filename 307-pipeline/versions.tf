# ===============================================
# [Terraform / Provider 버전]
#   → 버전은 정확히 고정한다(범위 연산자 금지) — 업그레이드는 숫자를 고치는 커밋으로만 한다.
# ===============================================
terraform {
  required_version = "1.15.8"

  # 서드파티 차트를 쓰지 않는다(전부 자체 매니페스트) → helm 프로바이더 없음
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
  }
}
