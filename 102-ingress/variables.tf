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

variable "ingress_nginx_chart_version" {
  description = "ingress-nginx 차트 버전"
  type        = string
  default     = "4.15.1"
}

# ===============================================
# [진입점 VIP]
#   → 이 저장소에서 브라우저용 주소의 유일한 정의 지점이다. 노드 IP 가 아니라 이 주소
#     하나가 /etc/hosts 에 들어가고, MetalLB 가 살아 있는 노드로 옮겨 준다.
#   ⚠ 노드망(192.168.56.0/24) 안이면서 노드·DHCP 와 겹치지 않아야 한다 — L2 모드는
#     같은 브로드캐스트 도메인에서 ARP 로 광고하는 방식이라 다른 대역은 응답하지 못한다.
# ===============================================

# 네트워크 환경마다 달라지는 값이라 default 없음 → tfvars 강제
variable "ingress_vip" {
  description = "ingress-nginx LoadBalancer VIP — Ansible host.yml 의 ingress_vip 와 글자 그대로 같아야 한다"
  type        = string
}

# ===============================================
# [ingress-nginx 워크로드]
# ===============================================

# 1 이면 그 파드가 곧 전 서비스의 SPOF 다(NodePort 시절보다 나빠진다) → 최소 2.
# 3 이상은 노드 수만큼만 의미가 있다 — 아래 antiAffinity 가 노드당 1개로 제한한다.
variable "ingress_replicas" {
  description = "ingress-nginx 컨트롤러 복제 수 (노드 분산 — 노드 수를 넘기면 초과분이 Pending 에 걸린다)"
  type        = number
  default     = 2
}

# ===============================================
# [다른 스택이 소유한 값의 미러]
# ===============================================

variable "metallb_namespace" {
  description = "MetalLB 네임스페이스 (101-metallb 소유 — CR 배치 위치 미러 선언)"
  type        = string
  default     = "metallb-system"
}
