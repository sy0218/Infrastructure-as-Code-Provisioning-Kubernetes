# ===============================================
# [Strimzi Cluster Operator]
#
# → Kubernetes에서 Kafka를 CR 기반으로 관리하기 위한
#   Strimzi Operator와 CRD를 설치한다.
#
# → 실제 Kafka 클러스터는 301-kafka에서 CR로 생성한다.
#
# [구성 흐름]
#   104-strimzi
#      └─ Strimzi Operator + CRD 설치
#                ↓
#   301-kafka
#      └─ Kafka / KafkaNodePool / KafkaTopic CR 생성
#                ↓
#   Strimzi Operator
#      └─ Kafka Pod / Service / PVC 등을 생성/관리
#
# [주의] 301-kafka보다 먼저 적용해야 한다.
# → Kafka CRD가 없으면 Kafka 리소스를 생성할 수 없다.
#
# [주의] Strimzi 이미지는 quay.io에서 직접 Pull한다.
# → Operator가 Kafka/Entity Operator 이미지도 관리하므로
#   Strimzi 버전과 이미지 태그가 연동된다.
#
# [주의] Helm upgrade만으로 CRD가 갱신되지 않는다.
# → Strimzi 버전 변경 시 CRD는 별도로 갱신해야 한다.
# ===============================================
resource "helm_release" "strimzi" {
  name       = "strimzi"
  repository = "oci://quay.io/strimzi-helm"
  chart      = "strimzi-kafka-operator"
  version    = var.strimzi_chart_version

  namespace        = var.namespace
  create_namespace = true
  timeout          = 600

  values = [yamlencode({
    # -------------------------------------------
    # [감시 범위]
    # → 모든 Namespace의 Strimzi 리소스를 감시한다.
    # -------------------------------------------
    watchAnyNamespace = true

    # -------------------------------------------
    # [NetworkPolicy]
    # → Strimzi가 Kafka용 NetworkPolicy를 생성하지 않는다.
    # -------------------------------------------
    generateNetworkPolicy = false

    # -------------------------------------------
    # [리소스]
    # → CPU/Memory Request만 설정하고 Limit은 사용하지 않는다.
    # -------------------------------------------
    resources = {
      requests = {
        cpu    = "100m"
        memory = "384Mi"
      }
      limits = null
    }
  })]
}
