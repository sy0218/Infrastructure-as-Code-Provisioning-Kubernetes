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
# [Strimzi 버전]
#
# → Helm Chart 버전 = Strimzi Operator 버전 = Operator 이미지 태그
# → Kafka 이미지 버전도 이 버전을 기준으로 결정된다.
#
# [주의] 버전 변경 시 CRD는 별도로 갱신해야 한다.
# → Helm upgrade만으로는 Strimzi CRD가 자동 갱신되지 않는다.
#
# 버전 변경 순서:
# 1. 버전 변경 → terraform apply
# 2. 해당 버전의 CRD 수동 적용
# 3. CRD 버전 확인
# -----------------------------------------------
variable "strimzi_chart_version" {
  description = "strimzi-kafka-operator Helm 차트 버전 (= 오퍼레이터/이미지 버전)"
  type        = string
}

# -----------------------------------------------
# [네임스페이스]
# -----------------------------------------------
variable "namespace" {
  description = "Strimzi 오퍼레이터 네임스페이스"
  type        = string
}
