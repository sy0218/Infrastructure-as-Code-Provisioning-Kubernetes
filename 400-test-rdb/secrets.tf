# ===============================================
# [Secret — test-rdb-secrets]
#   → 소스 RDB 4종이 자기 계정을 만들 때 쓰는 비밀번호. 공용 Secret(data-layer-secrets)에
#     넣지 않는 이유는 소유권이다 — 저쪽은 300 이 소유하고 파이프라인 전 워크로드가
#     envFrom 으로 통째로 받는데, 테스트 픽스처의 계정을 거기 섞으면 지울 때 같이 못 지운다.
#   → kubernetes_manifest 가 아니라 typed 리소스를 쓴다(매니페스트는 state 에 평문으로 남는다).
# ===============================================
resource "kubernetes_secret_v1" "test_rdb" {
  metadata {
    name      = "test-rdb-secrets"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/part-of"   = "data-layer"
      "app.kubernetes.io/component" = "test-rdb"
    }
  }

  type = "Opaque"

  # 키 이름이 각 이미지가 읽는 env 이름 그대로다 — 워크로드가 envFrom 없이
  # secretKeyRef 로 필요한 키만 집어 간다(이미지마다 읽는 이름이 달라서).
  data = {
    # Oracle: SYS/SYSTEM · 업무 스키마(APP_USER) · LogMiner 계정 셋이 같은 값을 쓴다
    ORACLE_PASSWORD   = var.cdc_source_db_password
    APP_USER_PASSWORD = var.cdc_source_db_password
    DBZ_PASSWORD      = var.cdc_source_db_password

    # SQL Server: 커넥터가 sa 로 붙는다(별도 CDC 전용 계정을 두지 않은 것은 랩 전제)
    MSSQL_SA_PASSWORD = var.cdc_source_db_password

    # PostgreSQL: POSTGRES_USER 가 슈퍼유저라 이 하나로 끝난다
    POSTGRES_PASSWORD = var.cdc_source_db_password

    # MySQL: root 는 initdb 스크립트가 GRANT 를 걸 때, cdc 는 커넥터가 붙을 때 쓴다
    MYSQL_ROOT_PASSWORD = var.cdc_source_db_password
    MYSQL_PASSWORD      = var.cdc_source_db_password
  }
}
