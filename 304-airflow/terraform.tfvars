# ===============================================
# [환경별 설정]
#   → 여기 없는 값은 전부 variables.tf 기본값으로 동작한다.
#   ⚠ 커밋되는 파일이라 시크릿 금지 — 시크릿은 secrets.auto.tfvars 로 넣는다.
# ===============================================

# build_and_push.sh 의 REGISTRY 와 같은 값.
# ⚠ ':80' 생략 불가 — 콜론/점 없는 단일 라벨은 Docker 참조 파서가 레지스트리로 인정하지
#   않고 docker.io 네임스페이스로 정규화한다(그러면 pull 이 Docker Hub 로 가서 전 파드
#   ImagePullBackOff). 노드 containerd 의 certs.d 신뢰 문자열도 "data-layer-harbor:80" 이다.
harbor_registry = "data-layer-harbor:80"

# build_and_push.sh 에 넘긴 값과 같은 값.
# ⚠ v0.1.0 재사용 금지 — 코드 베이크 전환으로 airflow 이미지 내용이 바뀌었다(불변 태그 규칙).
#   태그가 바뀌어야 init Job 이름(airflow-init-<태그>)도 바뀌어 불변 spec.template 충돌이 없다.
image_tag = "v0.2.0"

# ⚠ 임시값(2026-08-04) — 원래 기본값은 1 이다. 랩 메모리를 아끼려고 꺼 둔다.
#   triggerer 는 deferrable 오퍼레이터 전용인데 현재 DAG 3종엔 하나도 없어 손실이 없다.
#   deferrable 을 쓰기 시작하면 이 줄을 지워야 태스크가 영원히 deferred 에 머물지 않는다.
triggerer_replicas = 0

# 데이터 스토어 접속
# ⚠ 300-data-layer-base 의 values.yaml(global.postgresHost·minioEndpoint)과 같은 값이어야 한다.
# PostgreSQL 은 303-postgres 의 CNPG 클러스터(-rw = 항상 현재 primary) — 노드 IP 가 아니다.
postgres_host  = "data-layer-postgres-rw.data-layer.svc.cluster.local"
minio_endpoint = "http://192.168.56.200:9000"
