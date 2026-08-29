# ===============================================
#  [ terraform.tfvars ]
#    - variables.tf 에서 정의한 변수에 실제 값을 지정
# ===============================================

# Kubernetes 클러스터에 접속할 때 사용할 kubeconfig 파일 경로
kubeconfig_path = "~/.kube/config"

# Helm으로 설치할 cloudnative-pg 차트 버전 (차트 0.29.0 = 오퍼레이터 1.30.0)
cnpg_chart_version = "0.29.0"

# CloudNativePG 오퍼레이터 네임스페이스
namespace = "cnpg-system"