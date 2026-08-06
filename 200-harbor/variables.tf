# ===============================================
# [클러스터 접속]
#   → 이 스택이 Helm 으로 클러스터에 붙을 때 쓰는 유일한 인증 수단.
# ===============================================

variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}

# ===============================================
# [Harbor 접속 / 차트]
#   → host 는 externalURL · harbor 프로바이더 URL · Ingress 의 host · 전 스택
#     harbor_registry · 노드 containerd certs.d 디렉토리명의 단일 출처다.
#   → 이 주소가 실제 접속 주소와 어긋나면 docker login / push 가 깨진다.
# ===============================================

variable "harbor_chart_version" {
  description = "goharbor/harbor 차트 버전 (1.18.x = Harbor v2.14)"
  type        = string
  default     = "1.18.4"
}

variable "harbor_host" {
  description = "Harbor 접속 호스트명"
  type        = string
  default     = "data-layer-harbor"
}

variable "harbor_port" {
  description = "Harbor ClusterIP 포트 — Ingress 백엔드가 가리키는 포트 (차트 내부 nginx 8080 으로 전달)"
  type        = number
  default     = 80
}

# 이미지 레이어 하나가 느린 랩 네트워크에서 기본값 60초를 쉽게 넘긴다.
# 환경마다 달라질 값이 아니라 default 를 준다.
variable "harbor_proxy_timeout" {
  description = "Ingress 레이어 전송 대기 상한(초) — 넘으면 docker push 가 중간에 끊긴다"
  type        = string
  default     = "600"
}

# ⚠ 시크릿인데 default 평문 값이 이미 apply 된 상태와 묶여 있다 —
#   secrets.auto.tfvars 이관은 Harbor 비밀번호 교체와 같은 커밋에서만 한다.
variable "harbor_admin_password" {
  description = "Harbor admin 비밀번호 (lab 기본값 — 운영이면 반드시 교체)"
  type        = string
  default     = "Harbor12345"
  sensitive   = true
}

# ===============================================
# [영구 저장소]
#   → registry·database·redis·jobservice 4개를 longhorn 에 둔다 — 이유는 harbor.tf 참조.
#   ⚠ trivy 는 여기 안 걸려 local-path 로 떨어진다(취약점 DB 캐시 — 지워져도 재생성).
# ===============================================

# ⚠ longhorn replica 2 라 실제 디스크는 이 값의 2배를 먹는다(30Gi → 60Gi)
variable "harbor_registry_storage_size" {
  description = "Registry PVC 크기"
  type        = string
  default     = "30Gi"
}

variable "harbor_storage_class" {
  description = "Harbor PVC StorageClass — 아래 4개에만 적용된다(trivy 는 차트 기본값을 쓴다)"
  type        = string
  default     = "longhorn"
}

variable "harbor_component_storage_size" {
  description = "Harbor 내부 컴포넌트 PVC 크기"
  type        = string
  default     = "2Gi"
}
