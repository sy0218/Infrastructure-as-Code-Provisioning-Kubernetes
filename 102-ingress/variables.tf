# ===============================================
# [클러스터 접속]
# ===============================================

# → Terraform이 Kubernetes 클러스터에 접속할 때 사용하는 설정 파일이다.
variable "kubeconfig_path" {
  description = "Kubernetes 접속에 사용할 kubeconfig 경로"
  type        = string
  default     = "~/.kube/config"
}

# ===============================================
# [차트 버전]
# ===============================================

# → Helm으로 설치할 ingress-nginx 차트 버전이다.
# → 버전을 고정해 실행할 때마다 같은 버전을 사용한다.
variable "ingress_nginx_chart_version" {
  description = "ingress-nginx Helm 차트 버전"
  type        = string
  default     = "4.15.1"
}

# ===============================================
# [진입점 VIP]
#
# → 브라우저가 접속하는 대표 IP다.
# → 사용자는 노드 IP가 아닌 이 VIP로 접속한다.
# → MetalLB가 VIP를 현재 사용 가능한 노드에 연결한다.
#
# → MetalLB L2 모드는 ARP로 VIP를 네트워크에 광고한다.
# → 따라서 노드망(192.168.56.0/24)에서 사용해야 한다.
# → 노드나 DHCP가 이미 사용하는 IP와 겹치면 안 된다.
# ===============================================

# 네트워크 환경마다 달라지므로 기본값 없이 tfvars에서 지정한다.
variable "ingress_vip" {
  description = "Ingress VIP → Ansible host.yml의 ingress_vip와 동일한 값"
  type        = string
}

# ===============================================
# [PostgreSQL 외부 접속 VIP]
#
# → DBeaver 등 클러스터 밖 DB 클라이언트가 <이 IP>:5432 로 붙는다.
# → 인그레스 VIP 와 같은 노드망 제약(192.168.56.0/24, 미사용 IP)을 따른다.
# ===============================================

# 네트워크 환경마다 달라지므로 기본값 없이 tfvars에서 지정한다.
variable "postgres_vip" {
  description = "PostgreSQL 외부 접속 VIP → 303-postgres 의 externalIp 와 동일한 값"
  type        = string
}

# ===============================================
# [ingress-nginx 워크로드]
# ===============================================
# → 외부 요청을 받아 Kubernetes 내부 서비스로 전달한다.
# → 1개만 실행하면 해당 파드 장애 시 외부 접속이 끊길 수 있다.
# → 기본 2개로 실행해 서로 다른 노드에 분산한다.
# → 노드 수보다 많이 설정하면 초과 파드는 Pending 상태가 된다.

variable "ingress_replicas" {
  description = "Ingress 컨트롤러 복제 수 → 노드에 분산 배치"
  type        = number
  default     = 2
}

# ===============================================
# [다른 스택이 소유한 값의 미러]
# ===============================================
# → MetalLB 자체 설정은 101-metallb에서 관리한다.
# → 여기서는 MetalLB가 사용하는 네임스페이스만 참조한다.

variable "metallb_namespace" {
  description = "MetalLB 네임스페이스"
  type        = string
  default     = "metallb-system"
}