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
#   → 정확 고정 값이라 default 를 여기 둔다 — 업그레이드는 이 숫자를 고치는 커밋으로만.
# ===============================================

variable "local_path_chart_version" {
  description = "local-path-provisioner 차트 버전"
  type        = string
  default     = "0.0.37"
}

variable "longhorn_chart_version" {
  description = "longhorn 차트 버전 (차트 버전 = 앱 버전)"
  type        = string
  default     = "1.11.3"
}

# ===============================================
# [Longhorn 데이터 경로]
#   → 노드 디스크 구성마다 달라지는 값이라 default 를 주지 않고 tfvars 로 강제한다.
# ===============================================

variable "longhorn_data_path" {
  description = "Longhorn 데이터 경로"
  type        = string
}
