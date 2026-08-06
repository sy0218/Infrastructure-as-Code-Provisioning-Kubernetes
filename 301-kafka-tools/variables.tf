# ===============================================
# [클러스터 접속 / 공통]
# ===============================================

variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "데이터 레이어 네임스페이스 (300-data-layer-base 가 소유 — 여기서는 참조만)"
  type        = string
  default     = "data-layer"
}

# 아래 둘은 default 없음 → 환경/배포마다 달라지는 값이라 tfvars 강제
variable "harbor_registry" {
  description = "Harbor 레지스트리 주소(스킴 없음)"
  type        = string
}

variable "image_tag" {
  description = "배포할 이미지 태그(git SHA 기반 불변 태그)"
  type        = string
}

# ===============================================
# [워크로드]
#   → 브로커 주소는 여기 없다 — 300 이 만든 공용 ConfigMap 을 data 소스로 읽는다(locals.tf).
# ===============================================

variable "schema_registry_replicas" {
  description = "Schema Registry 복제 수 (stateless — 리더 선출이 내장이라 늘려도 안전)"
  type        = number
  default     = 1
}

# ===============================================
# [ClusterIP 포트 — 이 스택이 소유자]
#   → 포트 하나가 매니페스트 안에서 여러 번 나온다(프로세스 리슨 주소 · containerPort ·
#     Service port). 변수 하나에서 전부 주입해 어긋날 방법 자체를 없앤다.
#   → 환경마다 달라질 값이 아니라 default 를 준다.
#   ⚠ 300-data-layer-base 가 URL 문자열 조립용으로 미러 선언을 갖는 값이 둘 있다
#     (schema_registry_port · kafka_ui_host) — 바꾸면 같은 커밋에서 함께 고칠 것.
# ===============================================

variable "schema_registry_port" {
  description = "schema-registry ClusterIP/컨테이너 포트 — 300-data-layer-base 에 같은 이름의 미러 선언이 있다"
  type        = number
  default     = 9096
}

variable "kafka_ui_port" {
  description = "kafka-ui 컨테이너/ClusterIP 포트 — Ingress 백엔드가 가리키는 포트이기도 하다"
  type        = number
  default     = 9095
}

variable "kafka_exporter_port" {
  description = "kafka-exporter 메트릭 포트 — 리슨 주소·containerPort·Service port 가 이 값을 공유한다"
  type        = number
  default     = 9097
}

# ===============================================
# [외부 접속 — Ingress 호스트명]
#   → 이 이름이 Ingress 규칙의 host 이자 브라우저가 치는 주소다. 이름은 /etc/hosts 에서
#     102-ingress 의 VIP 로 풀리고(Ansible etc_hosts 롤), 노드 한 대가 죽으면 MetalLB 가
#     VIP 를 살아 있는 노드로 옮긴다 → 주소도 포트도 그대로다.
#   → 이름의 단일 출처는 README 접속 주소 표다.
# ===============================================

variable "kafka_ui_host" {
  description = "kafka-ui 접속 호스트명 — Ingress 규칙의 host (Ansible etc_hosts 가 VIP 로 푼다)"
  type        = string
  default     = "data-layer-kafka-ui"
}
