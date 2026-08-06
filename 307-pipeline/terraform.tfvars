# ===============================================
# [환경별 설정]
#   → 기본값 전체 목록은 variables.tf 참고.
#   → ⚠ 이 파일은 커밋된다 → 시크릿 금지(자격증명은 공용 Secret data-layer-secrets 에서 envFrom 으로 들어온다).
# ===============================================

# 이미지 출처: <harbor_registry>/data-layer/<name>:<image_tag>
harbor_registry = "data-layer-harbor"
image_tag       = "v0.1.0"

# 장비가 192.168.56.202 로 보내고 있어 s2 다 — 장비 설정이 바뀌면 이 값도 함께 움직인다.
tcp_socket_node_name = "s2"
