# ===============================================
# [ variables.tf ]
#   - Terraform 에서 사용할 입력 변수 정의
#   - 실제 값은 terraform.tfvars 에서 전달
#   - 설정값을 직접 하드코딩 않고 변수로 분리
# ===============================================


# -----------------------------------------------
# [클러스터 접속]
# -----------------------------------------------

# → Terraform이 Kubernetes 클러스터에 접속할 때 사용하는 설정 파일이다.
variable "kubeconfig_path" {
  description = "Kubernetes 접속에 사용할 kubeconfig 경로"
  type        = string
}

# -----------------------------------------------
# [차트 버전]
# -----------------------------------------------
variable "ingress_nginx_chart_version" {
  description = "ingress-nginx Helm 차트 버전"
  type        = string
}

# -----------------------------------------------
# [진입점 VIP]
#
# 외부 사용자가 Kubernetes에 접속할 때 사용하는 대표 IP다.
# 사용자는 노드 IP가 아닌 이 VIP로 접속한다.
#
# → MetalLB L2 모드는 ARP로 VIP를 네트워크에 광고한다.
# → 따라서 노드망(192.168.0.0/24)에서 사용해야 한다.
# → 노드나 DHCP가 이미 사용하는 IP와 겹치면 안 된다.
# -----------------------------------------------

variable "ingress_vip" {
  description = "Ingress VIP"
  type        = string
}

# -----------------------------------------------
# [PostgreSQL 외부 접속 VIP]
#
# 클러스터 외부의 DB 클라이언트가
# 이 IP의 5432 포트로 PostgreSQL에 접속한다.
#
# MetalLB가 사용하는 VIP이므로
# 노드 네트워크 대역(192.168.56.0/24)의
# 사용하지 않는 IP를 지정해야 한다.
# -----------------------------------------------

variable "postgres_vip" {
  description = "PostgreSQL 외부 접속 VIP → 303-postgres 의 externalIp 와 동일한 값"
  type        = string
}

# -----------------------------------------------
# [ingress-nginx 워크로드]
# -----------------------------------------------
# HTTP/HTTPS 외부 요청을 받아
# Host/Path( example.com/api ) 기준으로 Kubernetes 내부 Service에 전달한다.
#
# 1개만 실행하면 해당 Pod 장애 시 외부 접속이 끊길 수 있다.
# 기본 2개로 실행해 여러 노드에 분산 배치한다.
# -----------------------------------------------

variable "ingress_replicas" {
  description = "Ingress 컨트롤러 복제 수 → 노드에 분산 배치"
  type        = number
  default     = 2
}

# -----------------------------------------------
# [다른 스택이 소유한 값의 미러]
# -----------------------------------------------
# → MetalLB 자체 설정은 101-metallb에서 관리한다.
# → 여기서는 MetalLB가 사용하는 네임스페이스만 참조한다.

variable "metallb_namespace" {
  description = "MetalLB 네임스페이스"
  type        = string
}