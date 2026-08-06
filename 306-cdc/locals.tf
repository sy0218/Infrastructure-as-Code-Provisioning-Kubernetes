# ===============================================
# [공용 ConfigMap 참조]
#   → 브로커 주소의 출처는 300-data-layer-base 하나다. 값을 tfvars 로 복사하는 대신
#     클러스터에 실재하는 오브젝트를 읽어 두 스택이 어긋날 방법 자체를 없앤다(301 과 같은 방식).
#   ⚠ 300 이 apply 돼 있어야 이 스택의 plan 이 통과한다.
# ===============================================
data "kubernetes_config_map_v1" "shared" {
  metadata {
    name      = "data-layer-env"
    namespace = var.namespace
  }
}

locals {
  # configMapKeyRef 로 받은 값은 파드를 다시 만들지 않는 한 갱신되지 않는다 → 브로커 주소가
  # 바뀌면 이 해시가 바뀌어 롤아웃된다. 맵 전체가 아니라 소비 키만 해시하는 이유는
  # 무관한 키 변경에 워커를 재기동(=리밸런스)하지 않기 위함이다.
  connect_config_hash = sha256(data.kubernetes_config_map_v1.shared.data["KAFKA_BOOTSTRAP"])
}
