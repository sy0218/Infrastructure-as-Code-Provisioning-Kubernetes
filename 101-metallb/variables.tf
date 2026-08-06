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

variable "metallb_chart_version" {
  description = "metallb 차트 버전 (차트 버전 = 앱 버전)"
  type        = string
  default     = "0.16.1"
}

# ===============================================
# [네임스페이스]
#   → 102-ingress 가 이 값을 미러로 갖는다(CR 은 MetalLB 자기 네임스페이스에만 둘 수 있다).
# ===============================================

variable "namespace" {
  description = "MetalLB 네임스페이스 (이 스택이 소유·생성한다)"
  type        = string
  default     = "metallb-system"
}
