# ===============================================
# [환경별 설정]
#   → 여기 없는 값은 전부 variables.tf 기본값으로 동작한다.
#   ⚠ 이 파일은 커밋된다 → 시크릿 금지. 이 스택은 자격증명을 쓰지 않는다(git daemon 무인증).
# ===============================================

# 200-harbor 의 output harbor_registry 와 같은 값
harbor_registry = "data-layer-harbor"

# build_and_push.sh 에 넘긴 값과 같은 값
image_tag = "v0.1.1"
