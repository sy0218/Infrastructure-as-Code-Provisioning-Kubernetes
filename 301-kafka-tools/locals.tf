# ===============================================
# [공용 ConfigMap 참조]
#   → 브로커 목록의 출처는 300-data-layer-base 하나다. 값을 tfvars 로 복사하는 대신
#     클러스터에 실재하는 오브젝트를 읽어 두 스택이 어긋날 방법 자체를 없앤다.
#   ⚠ 300 이 apply 돼 있어야 이 스택의 plan 이 통과한다.
# ===============================================
data "kubernetes_config_map_v1" "shared" {
  metadata {
    name      = "data-layer-env"
    namespace = var.namespace
  }
}

# ===============================================
# [주소 조립]
#   → 클러스터 내부 주소는 FQDN 으로 적는다 — 짧은 이름은 ndots:5 때문에
#     search 도메인을 순회하는 실패 질의가 먼저 나간다.
# ===============================================
locals {
  svc_suffix = "${var.namespace}.svc.cluster.local"

  schema_registry_url = "http://schema-registry.${local.svc_suffix}:${var.schema_registry_port}"

  # '브라우저 → 클러스터'(Ingress)용. 브라우저는 svc.cluster.local 을 풀지 못하므로
  # 위의 Service DNS 와 서로를 대체할 수 없다. 포트가 없는 것은 인그레스가 VIP 의 80 을
  # 쓰기 때문이다 — 이 문자열은 300-data-layer-base 의 KAFKA_UI_URL 과 같아야 한다.
  kafka_ui_url = "http://${var.kafka_ui_host}"

  # envFrom/configMapKeyRef 값은 파드 재생성 없이 갱신되지 않는다 → 소비 키가 바뀌면
  # 이 해시가 바뀌어 롤아웃을 강제한다. 맵 전체가 아니라 소비 키만 해시하는 이유는
  # 무관한 키 변경에 재기동하지 않기 위함이다.
  kafka_ui_config_hash = sha256(join("|", [
    data.kubernetes_config_map_v1.shared.data["KAFKA_BOOTSTRAP"],
    data.kubernetes_config_map_v1.shared.data["SCHEMA_REGISTRY_URL"],
  ]))

  kafka_exporter_config_hash = sha256(data.kubernetes_config_map_v1.shared.data["KAFKA_BOOTSTRAP"])
}
