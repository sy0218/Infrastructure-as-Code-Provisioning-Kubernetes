# ===============================================
#  [ terraform.tfvars ]
#    - variables.tf 에서 정의한 변수에 실제 값을 지정
# ===============================================

# Kubernetes 클러스터에 접속할 때 사용할 kubeconfig 파일 경로
kubeconfig_path = "~/.kube/config"

# Helm으로 설치할 strimzi-kafka-operator 차트 버전 (차트 1.2.0 = 오퍼레이터 1.2.0 = Kafka 4.3.1 기본)
# [주의] 301-kafka values 의 kafka.version 이 이 오퍼레이터가 지원하는 버전(4.2.0~4.3.1)이어야 한다
strimzi_chart_version = "1.2.0"

# Strimzi 오퍼레이터 네임스페이스
namespace = "strimzi-system"
