# ===============================================
#  [ terraform.tfvars ]
#    - variables.tf 에서 정의한 변수에 실제 값을 지정
# ===============================================

# Kubernetes 클러스터에 접속할 때 사용할 kubeconfig 파일 경로
kubeconfig_path = "~/.kube/config"

# Helm 으로 설치할 ingress-nginx 차트의 버전
ingress_nginx_chart_version = "4.15.1"

# [주의] 이 값은 세 곳이 글자 그대로 같아야 한다.
#   1. 여기(Service 가 요청하는 IP)
#   2. /etc/hosts 가 이름을 이 IP 로 푼다
#   3. 305-api 의 ingress_vip (파드 hostAliases → 파드도 같은 이름으로 나가야 한다)
ingress_vip = "192.168.56.240"

# PostgreSQL 외부 접속 VIP (TCP 5432 → 인그레스를 못 타는 비-HTTP 라 전용 VIP)
# [주의] 303-postgres values.yaml 의 externalIp 와 같은 값 → 바꾸면 같은 커밋에서 함께.
postgres_vip = "192.168.56.241"

# ingress-nginx 컨트롤러 복제 수
ingress_replicas = 2

# MetalLB 네임스페이스
metallb_namespace = "metallb-system"
