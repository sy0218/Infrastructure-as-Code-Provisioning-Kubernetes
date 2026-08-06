# ===============================================
# [CDM Mapper ×8]
#   → raw.* → CDM 표준화 → cdm-topic. 8종의 차이는 실행 모듈 하나뿐이라 템플릿 1개 + for_each 로 만든다.
#   → for_each 키는 모듈명이다 — 인덱스로 돌리면 목록에서 하나만 빠져도 전부 재생성된다.
# ===============================================

locals {
  # 모듈명은 스네이크(파이썬 규칙), K8s 오브젝트 이름은 케밥(RFC 1123).
  # 변환은 여기 한 곳에서만 하고 템플릿과 output 은 이 값을 받아 쓰기만 한다.
  cdm_mapper_deployment_names = {
    for m in var.cdm_mapper_modules : m => "cdm-mapper-${replace(m, "_", "-")}"
  }
}

resource "kubernetes_manifest" "cdm_mapper" {
  for_each = toset(var.cdm_mapper_modules)

  manifest = yamldecode(templatefile("${path.module}/manifests/cdm-mapper.yaml.tftpl", {
    namespace                 = var.namespace
    image                     = "${var.harbor_registry}/data-layer/cdm-mapper:${var.image_tag}"
    module                    = each.key
    deployment_name           = local.cdm_mapper_deployment_names[each.key]
    replicas                  = var.cdm_mapper_replicas
    termination_grace_seconds = var.cdm_mapper_termination_grace_seconds
  }))
}
