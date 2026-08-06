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
# [저장소 볼륨]
#   → 이 스택의 존재 이유가 '노드가 죽어도 저장소가 살아있는 것'이라 볼륨이 핵심이다.
#     longhorn 이면 파드가 다른 노드로 옮겨갈 때 볼륨이 따라간다(Harbor·Grafana 와 같은 근거).
#   ⚠ RWO 라 Deployment 전략은 Recreate 여야 한다 — 매니페스트 주석 참조.
# ===============================================

variable "git_storage_size" {
  description = "bare 저장소 PVC 크기 — 코드만 담으므로 작게 잡는다"
  type        = string
  default     = "2Gi"
}

variable "git_storage_class" {
  description = "저장소 PVC 의 StorageClass (노드 이동성이 목적이라 longhorn)"
  type        = string
  default     = "longhorn"
}

# ===============================================
# [저장소 서버]
#   → 폐쇄망 랩이라 웹 UI·계정 체계가 필요 없어 Gitea 대신 git daemon 하나만 띄운다.
#   ⚠ git daemon 에는 인증이 없다. push 를 켜는 순간 이 포트에 닿는 누구나 쓸 수 있다 —
#     Harbor 가 TLS 없는 HTTP 인 것과 같은 수준의, 사설망 전제 위에서만 성립하는 타협이다.
# ===============================================

variable "git_daemon_port" {
  description = "git 프로토콜 포트 — 컨테이너/ClusterIP 공통(git 의 well-known 포트)"
  type        = number
  default     = 9418
}

# 저장소가 여럿 필요해지면 그때 목록으로 바꾼다(지금은 airflow 코드 하나뿐).
variable "git_repo_name" {
  description = "bare 저장소 이름 — 실제 경로는 /srv/git/<이름>.git 이 된다"
  type        = string
  default     = "airflow"
}

# ===============================================
# [외부 접속 — NodePort + 호스트명]
#   → 로컬 PC 에서 `git push` 할 때 쓰는 주소다. 클러스터 안(git-sync)은 같은 Service 의
#     ClusterIP 를 FQDN 으로 부르므로 이 이름을 쓰지 않는다.
#   → 이름·번호 전체 표의 소유자는 README 다.
# ===============================================

variable "git_host" {
  description = "git push 대상 호스트명 — 세 노드 IP 를 A 레코드로 갖는다(Ansible etc_hosts)"
  type        = string
  default     = "data-layer-git"
}

# 9418 을 그대로 못 쓰는 이유: NodePort 는 30000-32767 범위다. 번호만 9418 을 연상시키게 잡았다.
variable "git_nodeport" {
  description = "git daemon NodePort (30000-32767)"
  type        = number
  default     = 30418
}
