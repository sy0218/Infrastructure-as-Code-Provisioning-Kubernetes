variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}

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

variable "longhorn_data_path" {
  description = "Longhorn 데이터 경로"
  type        = string
  # default 없음 → 환경(노드 디스크 구성)마다 달라지는 값이라 tfvars 강제
}
