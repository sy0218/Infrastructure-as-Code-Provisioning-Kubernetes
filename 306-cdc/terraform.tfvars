# ===============================================
# [환경별 설정]
#   → 변수 정의와 기본값 전체 목록은 variables.tf 참고.
#   ⚠ 이 파일은 커밋된다 → 시크릿 금지. CDC 소스 RDB 비밀번호는 Terraform 이 아니라
#     커넥터 등록 JSON 에 사람이 채워 넣는다.
# ===============================================

# 이미지 출처: <harbor_registry>/data-layer/<name>:<image_tag> — 태그는 build_and_push.sh 에 넘긴 값과 같아야 한다
harbor_registry = "data-layer-harbor:80" # ⚠ :80 생략 시 docker.io 로 정규화 — build_and_push.sh 헤더 참조
image_tag       = "v0.1.0"

# ⚠ 임시값(2026-08-04) — 원래 기본값은 3 이다. 304-airflow 를 올릴 메모리를 확보하려고
#   2 로 내렸다(그 시점 커넥터 0건이라 실손실 없음). 노드 증설 후 이 줄을 지우면 3 으로 돌아간다.
#   배경: README '용량' 절.
connect_replicas = 2
