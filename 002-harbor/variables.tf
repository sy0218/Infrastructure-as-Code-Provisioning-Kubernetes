#########################################
# 클러스터 접속
#########################################
variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}

#########################################
# Harbor
#########################################
variable "harbor_chart_version" {
  description = "goharbor/harbor 차트 버전 (1.18.x = Harbor v2.14)"
  type        = string
  default     = "1.18.4"
}

variable "harbor_external_ip" {
  description = "Harbor 외부 접속 IP (아무 노드 IP — externalURL 및 push/pull 주소가 됨)"
  type        = string
}

variable "harbor_nodeport" {
  description = "Harbor HTTP NodePort (30000-32767)"
  type        = number
  default     = 30002
}

variable "harbor_admin_password" {
  description = "Harbor admin 비밀번호 (lab 기본값 — 운영이면 반드시 tfvars 로 교체)"
  type        = string
  default     = "Harbor12345"
  sensitive   = true
}

variable "harbor_registry_storage_size" {
  description = "이미지 레이어가 쌓이는 registry PVC 크기"
  type        = string
  default     = "20Gi"
}
