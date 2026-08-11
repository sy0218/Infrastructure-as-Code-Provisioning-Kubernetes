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

variable "metallb_chart_version" {
  description = "metallb 차트 버전"
  type        = string
  default     = "0.16.1"
}

# ===============================================
# [네임스페이스]
# ===============================================

variable "namespace" {
  description = "MetalLB 네임스페이스"
  type        = string
  default     = "metallb-system"
}
