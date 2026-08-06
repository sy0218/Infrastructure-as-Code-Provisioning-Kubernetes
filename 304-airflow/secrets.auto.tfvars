# ===============================================
# [시크릿 입력 예시]
#   → cp secrets.auto.tfvars.example secrets.auto.tfvars 후 값을 채운다.
#   → *.auto.tfvars 는 .gitignore 대상이라 커밋되지 않는다(.example 만 커밋).
#   → 아래는 랩 값 — 운영이면 전부 교체할 것.
# ===============================================

# Airflow 메타DB 접속 — ⚠ 300-data-layer-base 의 secrets.auto.tfvars 와 같은 계정이어야 한다
postgres_user     = "data_layer"
postgres_password = "data_layer123!"

# MinIO S3 자격증명 (config 버킷 읽기 + airflow-logs 쓰기)
# ⚠ 300-data-layer-base 의 minio_root_user / minio_root_password 와 같은 값이어야 한다
minio_access_key = "data_layer"
minio_secret_key = "data_layer123!"

# 4개 컴포넌트가 공유해야 하는 서명 키 (다르면 JWT 검증 실패로 태스크가 전부 죽는다)
airflow_api_secret_key = "wEc6oXXuAGIEg93jpoZQSn0cZAUa9LBT0uwijzHS0vQ="
airflow_jwt_secret     = "cZzxGk6srDlh1dqcdW+mDdi1SmXuKsfiw2HCC5XVOU0="

# 메타DB 에 저장된 Connection/Variable 복호화 키 — 교체하면 기존 값을 못 읽는다
airflow_fernet_key = "gqK-Zndp9NivexPVkY2umbLMS4r9-Sg9gmgZ5vd7Xtc="

# 초기 관리자 계정 (init Job 이 생성)
airflow_admin_username = "airflow"
airflow_admin_password = "airflow"
