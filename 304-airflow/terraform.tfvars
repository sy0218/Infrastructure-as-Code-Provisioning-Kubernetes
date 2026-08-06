# ===============================================
# [환경별 설정]
#   → 여기 없는 값은 전부 variables.tf 기본값으로 동작한다.
#   ⚠ 커밋되는 파일이라 시크릿 금지 — 시크릿은 secrets.auto.tfvars 로 넣는다.
# ===============================================

# 200-harbor 의 output harbor_registry 와 같은 값
harbor_registry = "data-layer-harbor"

# build_and_push.sh 에 넘긴 값과 같은 값
image_tag = "v0.1.0"

# ⚠ 임시값(2026-08-04) — 원래 기본값은 1 이다. 랩 메모리를 아끼려고 꺼 둔다.
#   triggerer 는 deferrable 오퍼레이터 전용인데 현재 DAG 3종엔 하나도 없어 손실이 없다.
#   deferrable 을 쓰기 시작하면 이 줄을 지워야 태스크가 영원히 deferred 에 머물지 않는다.
triggerer_replicas = 0

# 코드 원본 — 303-git 의 output git_repo_url 과 같은 값이어야 한다.
# (클러스터 안 주소다. 로컬에서 push 할 때 쓰는 주소는 303-git 의 output git_push_url)
git_repo = "git://data-layer-git.data-layer.svc.cluster.local:9418/airflow.git"

# 로컬 데이터 스토어(노드 로컬 설치 — Ansible, 추후 작성)
# ⚠ 300-data-layer-base 의 terraform.tfvars 와 같은 값이어야 한다.
postgres_host  = "192.168.56.200"
minio_endpoint = "http://192.168.56.200:9000"
