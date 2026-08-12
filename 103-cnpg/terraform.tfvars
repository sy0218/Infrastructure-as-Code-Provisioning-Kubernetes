# ===============================================
# [환경별 설정]
#   → 이 스택이 받는 값 전체를 여기 모아 둔다
# ===============================================

# Kubernetes 클러스터에 접속할 때 사용할 kubeconfig 파일 경로
kubeconfig_path = "~/.kube/config"

# Helm으로 설치할 cloudnative-pg 차트 버전 (차트 0.29.0 = 오퍼레이터 1.30.0)
cnpg_chart_version = "0.29.0"

# CloudNativePG 오퍼레이터 네임스페이스
namespace = "cnpg-system"

# 오퍼레이터 이미지는 Harbor 경유 (노드 containerd 가 Harbor 만 insecure 신뢰)
harbor_registry    = "data-layer-harbor:80"
operator_image_tag = "v0.1.0" # build_and_push.sh 에 넘긴 태그와 같은 값
