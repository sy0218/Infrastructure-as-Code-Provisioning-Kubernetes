# ===============================================
# [Terraform / Provider 버전]
#   → 전부 정확히 고정한다. 범위 연산자(>=, ~>) 금지 —
#     업그레이드는 버전 숫자를 고치는 커밋으로만.
# ===============================================

terraform {
  required_version = "1.15.8"

  # 공식 airflow 차트 대신 우리 이미지 + Deployment 를 직접 정의한다 → helm 프로바이더 없음
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
  }
}
