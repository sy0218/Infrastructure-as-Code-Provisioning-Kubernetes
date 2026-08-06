# ===============================================
# [클러스터 접속 / 공통]
# ===============================================

variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}

# 네임스페이스는 300-data-layer-base 가 만든다 — 여기서는 이름으로 참조만 한다
variable "namespace" {
  description = "데이터 레이어 네임스페이스 (300-data-layer-base 소유)"
  type        = string
  default     = "data-layer"
}

# 환경마다 달라지는 값이라 default 없음 → tfvars 강제
variable "harbor_registry" {
  description = "Harbor 레지스트리 주소(스킴 없음)"
  type        = string
}

variable "image_tag" {
  description = "배포할 이미지 태그(git SHA 기반 불변 태그)"
  type        = string
}

# ===============================================
# [CDM Mapper (raw.* → cdm-topic)]
# ===============================================

# 모듈명은 data_layer_mappers/<모듈>.py 와 1:1 이고 실행은 `python -m cdm.data_layer_mappers.<모듈>`.
# ⚠ 이 이름이 곧 파드 라벨 cdm.mapper/module 값이고 data-layer-api 의 DQ 적용이 그 라벨로
#   재기동 대상을 고른다 — 오타는 '적용은 성공했는데 아무것도 안 바뀜'으로 나타난다.
variable "cdm_mapper_modules" {
  description = "매퍼 모듈 목록 (Deployment 이름은 케밥으로 변환한 cdm-mapper-<모듈>)"
  type        = list(string)
  default = [
    "qm_chemical_batches",
    "qm_chemical_event_logs",
    "qm_chemical_replacement_history",
    "qm_chemical_control_loop_defs",
    "qm_chemical_qc_results",
    "qm_chemical_lab_results",
    "qm_chemical_claims",
    "qm_chemical_sensor_timeseries",
  ]
}

# ⚠ 유효 병렬도의 상한은 소스 토픽 파티션 수(현재 3)다. 그 이상의 replica 는 파티션을
#   배정받지 못해 유휴로 남는다 — 늘리려면 토픽 파티션 확대가 선행이다.
variable "cdm_mapper_replicas" {
  description = "매퍼 1종당 복제 수"
  type        = number
  default     = 1
}

# ⚠ 300-data-layer-base 의 ConfigMap 값 DATA_QUALITY_RESTART_DRAIN_TIMEOUT(=180)과 커플링돼 있다.
#   드레인 시간보다 작으면 커밋 전 배치가 잘려 재기동 시 중복 처리가 난다(180 + 여유 20).
variable "cdm_mapper_termination_grace_seconds" {
  description = "매퍼 SIGTERM 후 SIGKILL 까지의 유예(초)"
  type        = number
  default     = 200
}

# ===============================================
# [CDM Consumer (cdm-topic → 저장소)]
# ===============================================

# 매퍼와 같은 이유로 cdm-topic 파티션 수가 상한이다
variable "cdm_consumer_replicas" {
  description = "컨슈머 1종당 복제 수"
  type        = number
  default     = 1
}

# 마이크로배치 타임아웃(*_BATCH_TIME = 60초) 중에 죽으면 커밋 전 배치가 잘린다 → 배치 시간 + 여유.
# 매퍼(200)와 달리 DQ 드레인이 걸리지 않아 짧게 잡는다.
variable "cdm_consumer_termination_grace_seconds" {
  description = "컨슈머/계보 워커의 SIGTERM 후 유예(초)"
  type        = number
  default     = 90
}

# ===============================================
# [TCP Socket Collector (장비 push → raw.*)]
#   → 장비가 미는 대상 IP 가 고정돼야 해서 뜰 노드를 좁힌다 — 저장소에서 nodeSelector 를 쓰는 유일한 예외다.
#   → 매니페스트의 nodeSelector 와 outputs.tf 의 조회용 셀렉터 문자열이 이 변수 하나에서 나온다.
# ===============================================

# 파드의 nodeSelector 와 노드에 붙일 라벨이 이 변수 하나에서 나온다 → 둘이 어긋날 수 없다.
variable "tcp_socket_node_selector" {
  description = "TCP 수집기 파드를 배치할 노드 라벨(nodeSelector 맵)"
  type        = map(string)
  default     = { ingest = "true" }
}

# ⚠ 장비가 실제로 패킷을 보내는 노드여야 한다 — 틀리면 파드는 Running 인데 아무것도 받지 않는다(에러가 없어 알아채기 어렵다).
#   ap(control-plane)는 쓰지 않는다: 외부 장비 트래픽을 control-plane 으로 끌어들이지 않기 위해.
variable "tcp_socket_node_name" {
  description = "TCP 수집기를 띄울 노드 이름(이 노드에 위 라벨을 붙인다)"
  type        = string
}
