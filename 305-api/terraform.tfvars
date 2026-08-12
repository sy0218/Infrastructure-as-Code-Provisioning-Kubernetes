# ===============================================
# [환경별 설정]
#   → 변수 정의와 기본값 전체 목록은 variables.tf 참고.
#   ⚠ 이 파일은 커밋된다 → 시크릿 금지(자격증명은 공용 Secret data-layer-secrets 에서 envFrom 으로 들어온다).
# ===============================================

# 이미지 출처: <harbor_registry>/data-layer/<name>:<image_tag>
harbor_registry = "data-layer-harbor:80" # ⚠ :80 생략 시 docker.io 로 정규화 — build_and_push.sh 헤더 참조
image_tag       = "v0.1.0"

# 파드 /etc/hosts(hostAliases)용 — 클라이언트 PC hosts 파일에 넣는 VIP 와 같은 값이다.
# ⚠ 102-ingress 의 ingress_vip · Ansible host.yml 의 ingress_vip 와 글자 그대로 같아야 한다.
ingress_vip = "192.168.56.240"
