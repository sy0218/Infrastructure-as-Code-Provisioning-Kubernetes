# ===============================================
# [환경별 설정]
#   → 변수 정의와 기본값 전체 목록은 variables.tf 참고.
#   → ⚠ 이 파일은 커밋된다 → 시크릿 금지(시크릿은 secrets.auto.tfvars).
# ===============================================

# 각 스택 공통 — build_and_push.sh 의 REGISTRY 와 글자 그대로 같아야 한다.
# ⚠ 포트를 붙이지 않는다. Harbor 는 인그레스(VIP 의 80)로 노출되고, 노드 containerd 는
#   이 문자열과 똑같은 이름의 certs.d 디렉토리를 찾는다 — :30002 를 붙이면 그 이름이
#   달라져 insecure 설정이 적용되지 않고 HTTPS 로 붙어 pull 이 실패한다.
harbor_registry = "data-layer-harbor:80" # ⚠ :80 생략 시 docker.io 로 정규화 — build_and_push.sh 헤더 참조

# ⚠ build_and_push.sh 에 넘긴 태그와 같은 값. 태그는 불변으로 다루고 재사용하지 않는다.
image_tag = "v0.1.0"
