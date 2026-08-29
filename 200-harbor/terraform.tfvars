# ===============================================
#  [ terraform.tfvars ]
#    - variables.tf 에서 정의한 변수에 실제 값을 지정
# ===============================================

# Kubernetes 클러스터에 접속할 때 사용할 kubeconfig 파일 경로
kubeconfig_path = "~/.kube/config"

# Helm 으로 설치할 goharbor/harbor 차트 버전 (1.18.x = Harbor v2.14)
harbor_chart_version = "1.18.4"

# ===============================================
# [주의] Harbor 접속 주소
#
# → Harbor의 주소는 Docker 이미지 이름에도 사용된다.
#   예: data-layer-harbor/my-app:1.0
#
# → 따라서 Harbor 주소를 변경할 때는 아래 설정을
#   반드시 함께 수정해야 한다.
#
#   1. harbor_host
#   2. harbor_registry
#   3. externalURL
#   4. Harbor Provider URL
#   5. Ansible containerd insecure registry 설정
#
# → 하나라도 빠지면 Docker login / image push / image pull 등이
#   정상적으로 동작하지 않을 수 있다.
#
# ===============================================
harbor_host = "data-layer-harbor"

# Ingress 레이어 전송 대기 상한(초)
harbor_proxy_timeout = "600"

# Registry PVC 크기
harbor_registry_storage_size = "30Gi"

# registry/database/redis/jobservice/trivy 5개 PVC 의 StorageClass
harbor_storage_class = "local-path"

# Harbor 내부 컴포넌트 PVC 크기
harbor_component_storage_size = "2Gi"

# Harbor 컴포넌트 7 개를 전부 올릴 노드 (kubectl get nodes 의 NAME)
harbor_node_name = "s1"

# Trivy 취약점 DB 캐시 PVC 크기 (차트 기본값과 동일)
harbor_trivy_storage_size = "5Gi"
