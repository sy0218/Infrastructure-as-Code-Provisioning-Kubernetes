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

variable "local_path_chart_version" {
  description = "local-path-provisioner 차트 버전"
  type        = string
  default     = "0.0.37"
}

variable "longhorn_chart_version" {
  description = "longhorn 차트 버전"
  type        = string
  default     = "1.11.3"
}

# ===============================================
# [Longhorn 데이터 경로]
# ===============================================
variable "longhorn_data_path" {
  description = "Longhorn 데이터 경로"
  type        = string
}

# ===============================================
# [Longhorn 복제 갯수]
# ===============================================
variable "longhorn_replica_count" {
  description = "Longhorn 기본 StorageClass 의 볼륨 복제 수"
  type        = number
}
