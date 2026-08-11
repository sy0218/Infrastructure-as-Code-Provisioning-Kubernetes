# ===============================================
# [Kubernetes 접속]
#
# → Terraform이 Helm으로 Kubernetes에 접속할 때 사용하는 kubeconfig
#
# ===============================================

variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}


# ===============================================
# [Harbor 접속 / 버전]
#
# → Harbor의 접속 주소와 Helm Chart 버전을 설정한다.
#
# → harbor_host는 Harbor를 접속할 때 사용하는 주소이며,
#   Ingress / externalURL / containerd 설정에서도 동일하게 사용한다.
#
# ===============================================

variable "harbor_chart_version" {
  description = "Harbor Helm Chart 버전"
  type        = string
  default     = "1.18.4"
}

variable "harbor_host" {
  description = "Harbor 접속 호스트명"
  type        = string
  default     = "data-layer-harbor"
}

# ===============================================
# [Ingress]
#
# → Docker 이미지 Push/Pull이 오래 걸릴 수 있어
#   Ingress가 최대 600초까지 기다리도록 설정한다.
#
# ===============================================

variable "harbor_proxy_timeout" {
  description = "Ingress 요청 대기 시간(초)"
  type        = string
  default     = "600"
}


# ===============================================
# [Harbor 관리자 비밀번호]
#
# → secrets.auto.tfvars에서 값을 주입한다.
# → Terraform 출력에서는 비밀번호를 숨긴다.
#
# ===============================================

variable "harbor_admin_password" {
  description = "Harbor admin 비밀번호"
  type        = string
  sensitive   = true
}


# ===============================================
# [Harbor 저장소]
#
# → Registry / Database / Redis는 Longhorn을 사용한다.
# → Jobservice / Trivy는 local-path를 사용한다.
#
# ===============================================

variable "harbor_registry_storage_size" {
  description = "Registry PVC 크기"
  type        = string
  default     = "30Gi"
}

variable "harbor_storage_class" {
  description = "Registry / Database / Redis에 사용할 StorageClass"
  type        = string
  default     = "longhorn"
}

variable "harbor_component_storage_size" {
  description = "Database / Redis / Jobservice PVC 크기"
  type        = string
  default     = "2Gi"
}