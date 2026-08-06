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
# [data-layer-api 워크로드]
#   → api_port 하나가 컨테이너 포트 · ClusterIP 포트 · DATA_LAYER_API_PORT 로 함께 주입된다.
# ===============================================

# /quality/apply 가 매퍼 파드를 delete 하는 부수효과를 가져서, 두 파드가 동시에 처리하면
# 같은 매퍼를 두 번 죽인다 → 1 고정
variable "api_replicas" {
  description = "API 복제 수 (동시 /quality/apply 충돌 때문에 1 고정)"
  type        = number
  default     = 1
}

variable "api_port" {
  description = "API/관리 화면 리슨 포트 — 클러스터 내부 호출자가 쓰는 ClusterIP 포트이기도 하다"
  type        = number
  default     = 8090
}

# ===============================================
# [Grafana 서버사이드 호출 — 파드 hostAliases]
#   → '데이터 모니터링' 화면은 대시보드 '목록'만 이 API 가 대신 읽는다(브라우저가 직접 부르면
#     다른 출처라 CORS 에 막힌다). 대상 주소는 공용 ConfigMap 의 GRAFANA_URL 하나뿐인데,
#     그 값은 브라우저용 호스트명이고 CoreDNS 는 노드 /etc/hosts 를 보지 않는다
#     → 파드가 그 이름을 못 풀어 화면이 503 이 된다. 아래 둘로 파드 /etc/hosts 를 채운다.
#   → 인그레스 도입 전에는 노드 IP 3줄을 넣어 '죽은 노드면 다음 IP' 로 넘겼지만, 이제는
#     VIP 1줄이면 된다 — 장애 전환을 클라이언트가 아니라 MetalLB 가 하기 때문이다.
# ===============================================

# 네트워크 환경마다 달라지는 값 → default 없이 tfvars 강제
variable "ingress_vip" {
  description = "인그레스 VIP (102-ingress 소유 — hostAliases 조립용 미러 선언)"
  type        = string
}

variable "grafana_host" {
  description = "Grafana 접속 호스트명 (302-monitoring 소유 — hostAliases 조립용 미러 선언)"
  type        = string
  default     = "data-layer-grafana"
}

# ===============================================
# [외부 접속 — Ingress 호스트명]
#   → 호스트명 하나가 102-ingress 의 VIP 로 풀린다(Ansible etc_hosts 롤) → 노드 한 대가
#     죽어도 MetalLB 가 VIP 를 옮겨 접속 주소가 그대로다.
#   → 이름의 단일 출처는 README 접속 주소 표다.
# ===============================================

# 이 외부 이름은 ClusterIP Service 이름과 글자가 같다(의도한 것) — 해석 경로가 다르다.
#   파드 안       → CoreDNS → ClusterIP:api_port(8090)
#   클라이언트 PC → hosts   → VIP:80 → Ingress → 같은 Service
# ⚠ 이 이름에 닿으면 "/"(인증 없는 관리 화면)가 열린다("/api/*" 만 X-API-Key) — 사설망 전제.
variable "api_host" {
  description = "관리 화면/API 접속 호스트명 — Ingress 규칙의 host (Ansible etc_hosts 가 VIP 로 푼다)"
  type        = string
  default     = "data-layer-api"
}

# ingress-nginx 기본값은 1m 이고, DQ 규칙·도메인 설정 업로드가 그 선을 넘는다.
# 환경마다 달라질 값이 아니라 default 를 준다.
variable "api_proxy_body_size" {
  description = "Ingress 업로드 본문 크기 상한 (nginx proxy-body-size — 넘으면 413)"
  type        = string
  default     = "50m"
}

# ⚠ ingress-nginx 기본값은 60초인데 DQ '적용'은 그 안에 못 끝난다 — 매퍼 파드를 지우고
#   재기동 완료까지 HTTP 요청 안에서 기다리는 동기 경로이기 때문이다(quality_admin.py).
#   상한은 드레인(공용 ConfigMap 의 DATA_QUALITY_RESTART_DRAIN_TIMEOUT=180) + 60 = 240초라
#   반드시 그보다 커야 한다. NodePort(L4) 시절에는 중간에 HTTP 타임아웃이 없어 없던 제약이다.
variable "api_proxy_read_timeout" {
  description = "Ingress 백엔드 응답 대기 상한(초) — DQ 적용이 이 안에 안 끝나면 504"
  type        = string
  default     = "300"
}
