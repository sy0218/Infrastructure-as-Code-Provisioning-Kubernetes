# 버전은 전부 정확 고정(범위 연산자 금지) — 업그레이드는 이 숫자를 고치는 커밋으로만 일어난다
terraform {
  required_version = "1.15.8"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
  }
}
