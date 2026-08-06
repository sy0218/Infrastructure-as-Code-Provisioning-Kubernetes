# ===============================================
# [환경별 설정]
#   → 변수 정의와 기본값 전체 목록은 variables.tf 참고.
#   이 파일은 커밋된다 → 시크릿 금지(이 스택은 공용 Secret 을 이름으로만 참조해 자기 시크릿이 없다).
# ===============================================

# 이미지 출처: <harbor_registry>/data-layer/<name>:<image_tag>
harbor_registry = "data-layer-harbor"
image_tag       = "v0.1.0"
