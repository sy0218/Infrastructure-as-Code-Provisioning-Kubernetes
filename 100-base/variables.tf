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
  description = "kubeconfig 파일 경로"
  type        = string
}

# -----------------------------------------------
# [차트 버전]
# -----------------------------------------------
variable "local_path_chart_version" {
  description = "local-path-provisioner 차트 버전"
  type        = string
}

variable "longhorn_chart_version" {
  description = "longhorn 차트 버전"
  type        = string
}

# -----------------------------------------------
# [Longhorn 데이터 경로]
# -----------------------------------------------
variable "longhorn_data_path" {
  description = "Longhorn 데이터 경로"
  type        = string
}

# -----------------------------------------------
# [Longhorn 복제 갯수]
# -----------------------------------------------
variable "longhorn_replica_count" {
  description = "Longhorn 기본 StorageClass 의 볼륨 복제 수"
  type        = number
}
