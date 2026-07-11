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
