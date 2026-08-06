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
  description = "배포할 이미지 태그(불변 태그)"
  type        = string
}

# ===============================================
# [Prometheus]
#   → 보존기간과 PVC 크기는 한 쌍으로 본다 — 한쪽만 늘리면 디스크가 먼저 찬다.
#   → 단일 인스턴스라 앱 레벨 복제본이 없다 → 볼륨이 파드를 따라가야 해서 longhorn.
# ===============================================

variable "prometheus_retention" {
  description = "TSDB 보존기간"
  type        = string
  default     = "30d"
}

variable "prometheus_storage_size" {
  description = "Prometheus TSDB PVC 크기"
  type        = string
  default     = "20Gi"
}

variable "prometheus_storage_class" {
  description = "Prometheus PVC StorageClass"
  type        = string
  default     = "longhorn"
}

# 잡별로 주기를 달리 할 이유가 아직 없어 global 하나로 둔다
variable "global_scrape_interval" {
  description = "모든 잡에 적용되는 기본 스크랩 주기"
  type        = string
  default     = "30s"
}

# 브로커는 클러스터 밖(ADR 0 — Ansible 이 노드 로컬 systemd 로 설치)이라 kubernetes_sd 로
# 발견할 수 없다 → 노드 IP static 타깃. 노드 IP 는 환경마다 다르므로 default 없음.
variable "kafka_jmx_targets" {
  description = "Kafka 브로커 JMX exporter static 타깃 목록 — Ansible host.yml kafka 그룹(노드 IP:9404)과 일치해야 한다"
  type = list(object({
    address  = string # <노드 IP>:9404
    node     = string # 노드 이름 (ap/s1/s2) — 대시보드 by(node) 그룹화용
    instance = string # kafka-0/1/2 — K8s 파드명 시절 시계열과 이어 붙이기 위함
  }))
}

# ===============================================
# [Alloy]
# ===============================================

# ⚠ hostNetwork DaemonSet 이라 이 값은 '노드의 포트'다 — 노드가 이미 쓰는 포트와
#   겹치면 바인드 실패로 CrashLoop 에 빠진다(스케줄러는 이 충돌을 모른다).
variable "alloy_port" {
  description = "Alloy HTTP 서버 포트 (hostNetwork — 노드 포트를 그대로 점유한다)"
  type        = number
  default     = 12345
}

# 경로는 ConfigMap alloy-config(manifests/alloy-config.yaml.tftpl)의 컴포넌트 ID 에서 나온다 —
# 컴포넌트 이름을 바꾸면 Prometheus metrics_path 와 alloy readinessProbe 가 같이 깨진다.
variable "alloy_node_metrics_path" {
  description = "unix(node) exporter 컴포넌트의 메트릭 노출 경로"
  type        = string
  default     = "/api/v0/component/prometheus.exporter.unix.node/metrics"
}

variable "alloy_cadvisor_metrics_path" {
  description = "cadvisor 컴포넌트의 메트릭 노출 경로 (위와 동일한 결합 관계)"
  type        = string
  default     = "/api/v0/component/prometheus.exporter.cadvisor.containers/metrics"
}

# ===============================================
# [Grafana]
#   → 프로비저닝(데이터소스·대시보드)은 이미지에 구워져 있어 PVC 에 남는 것은
#     화면에서 편집한 것 + grafana.db 뿐이다.
# ===============================================

variable "grafana_storage_size" {
  description = "Grafana PVC 크기"
  type        = string
  default     = "5Gi"
}

variable "grafana_storage_class" {
  description = "Grafana PVC StorageClass (Prometheus 와 같은 이유로 longhorn)"
  type        = string
  default     = "longhorn"
}

# ===============================================
# [ClusterIP 포트 — 이 스택이 소유자]
#   → 포트 하나가 containerPort · Service port · output URL 여러 곳에 나온다.
#     변수 하나에서 주입해 어긋날 방법 자체를 없앤다(301·304·305 와 같은 규약).
# ===============================================

variable "prometheus_port" {
  description = "Prometheus 컨테이너/ClusterIP 포트 — Grafana 데이터소스가 부르는 포트"
  type        = number
  default     = 9090
}

variable "grafana_port" {
  description = "Grafana 컨테이너/ClusterIP 포트 — Ingress 백엔드가 가리키는 포트이기도 하다"
  type        = number
  default     = 3000
}

# ===============================================
# [외부 접속 — Ingress 호스트명]
#   → 서비스마다 자기 호스트명을 갖고, 그 이름이 102-ingress 의 VIP 로 풀린다
#     (Ansible etc_hosts) → 노드가 죽어도 MetalLB 가 VIP 를 옮겨 이름이 그대로다.
#   → 이름의 단일 출처는 README 접속 주소 표다.
# ===============================================

variable "grafana_host" {
  description = "Grafana 접속 호스트명 — 300-data-layer-base 의 GRAFANA_URL 과 같아야 iframe 임베드가 뜬다"
  type        = string
  default     = "data-layer-grafana"
}

variable "prometheus_host" {
  description = "Prometheus 디버깅 UI 접속 호스트명"
  type        = string
  default     = "data-layer-prometheus"
}
