# ===============================================
# [환경별 설정]
#   → 이 스택이 받는 값 전체를 여기 모아 둔다
# ===============================================

# Kubernetes 클러스터에 접속할 때 사용할 kubeconfig 파일 경로
kubeconfig_path = "~/.kube/config"

# Helm으로 설치할 Local Path Provisioner의 버전
local_path_chart_version = "0.0.37"

# Helm으로 설치할 Longhorn의 버전
longhorn_chart_version = "1.11.3"


# ===============================================
# [필수 설정]
# ===============================================
# Longhorn이 각 노드에서 데이터를 저장할 실제 디스크 경로
longhorn_data_path = "/data/longhorn"

# Longhorn 복제 데이터 갯수
longhorn_replica_count = 3
