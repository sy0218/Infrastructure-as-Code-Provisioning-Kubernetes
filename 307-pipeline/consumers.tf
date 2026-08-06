# ===============================================
# [CDM Consumer ×3]
#   → cdm-topic → 저장소(PG / Neo4j / Iceberg). 셋 다 같은 토픽을 각자의 컨슈머 그룹으로 읽어 하나가 죽어도 나머지 적재는 계속된다.
#   → 종류별로 다른 것은 '이미지 이름 + env 목록' 둘뿐이라 템플릿은 하나로 둔다.
# ===============================================

locals {
  # 종류별 차이의 단일 정의 지점.
  # from_config_map / from_secret 은 '코드가 읽는 이름 → 공용 오브젝트의 키' 번역표다.
  # 이름이 같은 값(KAFKA_BOOTSTRAP·CDM_TOPIC·CDM_CONSUMER_<종류>_GROUP 등)은 envFrom 으로
  # 그냥 들어오므로 적지 않는다 — 번역은 공용 키가 아니라 소비자 쪽에서 한다.
  cdm_consumers = {
    rdb = {
      image = "cdm-consumer-rdb"
      # PLATFORM_PG_DSN 을 코드가 그 이름 그대로 읽는다 → 번역할 것이 없다
      from_config_map = {}
      from_secret     = {}
    }

    graph = {
      image = "cdm-consumer-graph"
      # 공용 쪽 PLATFORM_ 접두는 '사내 플랫폼 그래프 계정'이라는 출처 표시다
      from_config_map = {
        NEO4J_URI      = "PLATFORM_NEO4J_URI"
        NEO4J_DATABASE = "PLATFORM_NEO4J_DATABASE"
      }
      from_secret = {
        NEO4J_USER     = "PLATFORM_NEO4J_USER"
        NEO4J_PASSWORD = "PLATFORM_NEO4J_PASSWORD"
      }
    }

    warehouse = {
      image = "cdm-consumer-warehouse"
      # 데이터 파일 저장소(S3)만 이름이 다르다 — MinIO 자격증명을 두 벌 관리하지 않으려고
      # ROOT 계정을 그대로 S3 키로 재사용한다.
      from_config_map = {
        ICEBERG_S3_ENDPOINT = "MINIO_S3_ENDPOINT"
      }
      from_secret = {
        ICEBERG_S3_ACCESS_KEY = "MINIO_ROOT_USER"
        ICEBERG_S3_SECRET_KEY = "MINIO_ROOT_PASSWORD"
      }
    }
  }

  # 워크로드 이름 = 라벨 app = 컨슈머 그룹 이름이 같은 문자열이다(갈리면 lag 대시보드에서
  # 어느 파드의 그룹인지 추측해야 한다). 매퍼와 같이 이름 조립은 여기 한 곳에서만 한다.
  cdm_consumer_deployment_names = {
    for kind in keys(local.cdm_consumers) : kind => "cdm-consumer-${kind}"
  }

  # 번역표 → 파드 env 배열. 값이 아니라 참조(valueFrom)로 넣어 자격증명이
  # Deployment 스펙에 남지 않게 한다. 맵 순회는 키 사전순이라 순서가 흔들리지 않는다.
  cdm_consumer_env = {
    for kind, c in local.cdm_consumers : kind => concat(
      [for k, v in c.from_config_map : {
        name      = k
        valueFrom = { configMapKeyRef = { name = "data-layer-env", key = v } }
      }],
      [for k, v in c.from_secret : {
        name      = k
        valueFrom = { secretKeyRef = { name = "data-layer-secrets", key = v } }
      }],
    )
  }
}

resource "kubernetes_manifest" "cdm_consumer" {
  # 키는 종류 이름(rdb/graph/warehouse) — 안정적인 문자열이라 목록이 바뀌어도 다른 항목이 안 흔들린다
  for_each = local.cdm_consumers

  manifest = yamldecode(templatefile("${path.module}/manifests/cdm-consumer.yaml.tftpl", {
    namespace                 = var.namespace
    name                      = local.cdm_consumer_deployment_names[each.key]
    image                     = "${var.harbor_registry}/data-layer/${each.value.image}:${var.image_tag}"
    replicas                  = var.cdm_consumer_replicas
    termination_grace_seconds = var.cdm_consumer_termination_grace_seconds

    # 종류마다 env 목록이 달라 tf 자료구조에서 와야 한다 → 한 줄 JSON 으로 넘긴다(JSON 은 YAML 의 부분집합).
    # ⚠ 빈 목록(rdb)일 때는 키 자체를 만들지 않는다 — `env: []` 는 API 서버가 지워 버려
    #   매니페스트와 실물이 어긋나고 apply 마다 차이가 보고된다(수렴하지 않는 plan).
    env_block = length(local.cdm_consumer_env[each.key]) > 0 ? "env: ${jsonencode(local.cdm_consumer_env[each.key])}" : ""
  }))
}
