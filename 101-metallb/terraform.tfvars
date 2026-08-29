# ===============================================
#  [ terraform.tfvars ]
#    - variables.tf 에서 정의한 변수에 실제 값을 지정
# ===============================================

# Kubernetes 클러스터에 접속할 때 사용할 kubeconfig 파일 경로
kubeconfig_path = "~/.kube/config"

# Helm으로 설치할 metallb_chart 의 버전
metallb_chart_version = "0.16.1"

# MetalLB 네임스페이스
namespace = "metallb-system"