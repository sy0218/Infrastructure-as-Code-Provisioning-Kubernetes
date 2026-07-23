###########################################
# 버전은 전부 정확히 고정(Pin)
# 범위 연산자는 사용하지 않는다.
# 업그레이드는 버전 번호를 수정하는 커밋으로만 수행한다.
###########################################

terraform {
  # Terraform CLI 버전
  required_version = "1.15.8"

  # Terraform에서 사용하는 Provider(플러그인) 버전
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
  }
}
