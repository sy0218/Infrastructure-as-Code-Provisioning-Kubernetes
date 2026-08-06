# ===============================================
# [클러스터 접속 / 공통]
#   → 네임스페이스와 공용 ConfigMap/Secret 은 300-data-layer-base 소유 — 여기서는 이름으로 참조만 한다.
#   → 환경마다 달라지는 값(harbor_registry·image_tag)은 default 를 주지 않아 tfvars 를 강제한다.
# ===============================================

variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "데이터 레이어 네임스페이스 (300-data-layer-base 소유)"
  type        = string
  default     = "data-layer"
}

variable "harbor_registry" {
  description = "Harbor 레지스트리 주소(스킴 없음)"
  type        = string
}

variable "image_tag" {
  description = "배포할 이미지 태그(git SHA 기반 불변 태그)"
  type        = string
}

# ===============================================
# [Kafka Connect (Debezium)]
#   → 워커는 디스크 상태도 고정 ID 도 갖지 않는다(설정/오프셋/상태가 전부 Kafka 내부 토픽).
#   → 그래서 워커 수를 바꾸면 그룹 리밸런스가 커넥터/태스크를 알아서 재배치한다.
# ===============================================

variable "connect_replicas" {
  description = "Connect 워커 수 (숫자만 바꾸면 확장/축소가 끝난다)"
  type        = number
  default     = 3
}

# ⚠ 포트의 소유자는 이 스택이다 — 300-data-layer-base 가 공용 ConfigMap 의 KAFKA_CONNECT_URL 을
#   조립하느라 kafka_connect_port 라는 미러 선언을 갖는다. 같은 커밋에서 함께 고칠 것.
variable "connect_rest_port" {
  description = "Connect REST 포트 (300-data-layer-base 에 kafka_connect_port 미러 선언이 있다)"
  type        = number
  default     = 8083
}

# ⚠ 이 값이 다른 워커는 '다른 클러스터'다 — 같은 내부 토픽을 봐도 커넥터를 나눠 갖지 않는다.
#   혼동을 줄이려고 Service 이름(cdc-connect)과 같은 값으로 맞춰 둔다.
variable "connect_group_id" {
  description = "Connect 클러스터 식별자"
  type        = string
  default     = "cdc-connect"
}

# 내부 토픽 3종 — 이름을 바꾸면 기존 상태를 못 읽는다
variable "connect_config_storage_topic" {
  description = "커넥터 설정 저장 토픽 (바꾸면 등록된 커넥터가 사라진 것처럼 보인다)"
  type        = string
  default     = "connect-configs"
}

variable "connect_offset_storage_topic" {
  description = "소스 커넥터 오프셋 저장 토픽 (바꾸면 CDC 가 처음부터 다시 스냅샷을 뜬다)"
  type        = string
  default     = "connect-offsets"
}

variable "connect_status_storage_topic" {
  description = "커넥터/태스크 상태 저장 토픽"
  type        = string
  default     = "connect-status"
}

# ⚠ 브로커 수보다 크면 토픽 생성이 실패해 워커가 기동 중 죽는다(브로커 3 → 3).
#   이 토픽들이 Connect 의 유일한 상태 저장소라 복제 없이 두면 브로커 1대 손실 = 설정 유실.
variable "connect_replication_factor" {
  description = "Connect 내부 토픽 3종의 복제계수"
  type        = number
  default     = 3
}
