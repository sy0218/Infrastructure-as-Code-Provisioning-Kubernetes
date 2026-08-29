# ===============================================
# [ variables.tf ]
#   - Terraform 에서 사용할 입력 변수 정의
#   - 실제 값은 terraform.tfvars 에서 전달
#   - 설정값을 직접 하드코딩 않고 변수로 분리
# ===============================================


# -----------------------------------------------
# [클러스터 접속]
# -----------------------------------------------
variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
}


# -----------------------------------------------
# [Harbor 접속 / 버전]
#
# → Harbor의 접속 주소와 Helm Chart 버전을 설정한다.
#
# → harbor_host는 Harbor를 접속할 때 사용하는 주소이며,
#   Ingress / externalURL / containerd 설정에서도 동일하게 사용한다.
#
# -----------------------------------------------

variable "harbor_chart_version" {
  description = "Harbor Helm Chart 버전"
  type        = string
}

variable "harbor_host" {
  description = "Harbor 접속 호스트명"
  type        = string
}

# -----------------------------------------------
# [Proxy Timeout]
#
# → Docker 이미지 Push/Pull 작업이 오래 걸릴 수 있어
#   Proxy 요청 대기 시간을 600초로 설정한다.
#
# -----------------------------------------------

variable "harbor_proxy_timeout" {
  description = "Ingress Proxy 요청 대기 시간(초)"
  type        = string
}


# -----------------------------------------------
# [Harbor 관리자 비밀번호]
#
# → secrets.auto.tfvars에서 값을 주입한다.
# → Terraform 출력에서는 비밀번호를 숨긴다.
#
# -----------------------------------------------

variable "harbor_admin_password" {
  description = "Harbor admin 비밀번호"
  type        = string
  sensitive   = true
}


# -----------------------------------------------
# [Harbor 저장소]
#
# → PVC 전부를 local-path 로 둔다.
# → 이미지 정본은 MinIO 의 tar 아카이브이고 Harbor 는 그 캐시라서,
#   노드/디스크를 잃어도 재설치 후 복원할 수 있다(Longhorn 복제 불필요).
#
# -----------------------------------------------

variable "harbor_registry_storage_size" {
  description = "Registry PVC 크기"
  type        = string
}

variable "harbor_storage_class" {
  description = "Harbor PVC 전체(registry/database/redis/jobservice/trivy)에 사용할 StorageClass"
  type        = string
}

variable "harbor_component_storage_size" {
  description = "Database / Redis / Jobservice PVC 크기"
  type        = string
}

variable "harbor_trivy_storage_size" {
  description = "Trivy 취약점 DB 캐시 PVC 크기"
  type        = string
}

# -----------------------------------------------
# [배치 노드]
#
# → Harbor 컴포넌트 7개를 단일 노드에 배치한다.
# → MinIO 에 이미지를 백업하므로 노드 분산의 필요성이 낮다.
# → local-path PV가 노드에 종속되므로 배치 노드 변경 시 재설치가 필요하다.
# → ap 는 control-plane taint 때문에 제외한다 (toleration 없이는 뜨지 않는다).
# -----------------------------------------------
variable "harbor_node_name" {
  description = "Harbor 컴포넌트 전체를 배치할 노드 이름 (kubernetes.io/hostname)"
  type        = string
}
