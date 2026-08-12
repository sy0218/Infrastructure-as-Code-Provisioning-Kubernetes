# ===============================================
# [클러스터 접속]
# ===============================================

variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}

# ===============================================
# [차트 버전]
# ===============================================

variable "cnpg_chart_version" {
  description = "cloudnative-pg 차트 버전"
  type        = string
  default     = "0.29.0"
}

# ===============================================
# [네임스페이스]
# ===============================================

variable "namespace" {
  description = "CloudNativePG 오퍼레이터 네임스페이스"
  type        = string
  default     = "cnpg-system"
}

# ===============================================
# [이미지]
#
# 오퍼레이터 이미지도 Harbor 경유가 필수라(노드 containerd 신뢰 범위)
# 환경 의존 값 → default 없음, tfvars 강제.
# ===============================================

variable "harbor_registry" {
  description = "Harbor 레지스트리 주소 (예: data-layer-harbor:80)"
  type        = string
}

variable "operator_image_tag" {
  description = "Harbor 에 push 한 cloudnative-pg 이미지 태그 (build_and_push.sh 에 넘긴 값)"
  type        = string
}
