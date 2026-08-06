# ===============================================
# [Terraform Output]
#   → 조회: terraform -chdir=400-test-rdb output -json cdc_source_endpoints
#   → 아래 넷이 이 스택의 유일한 대외 계약이다. 커넥터 JSON 4종의 database.hostname/port 와
#     Airflow 커넥션(cdc_oracle·cdc_mssql·cdc_postgres·cdc_mysql)이 이 값과 같아야 한다.
# ===============================================

output "cdc_source_endpoints" {
  description = "커넥터/Airflow 가 붙는 소스 RDB 4종의 클러스터 내부 주소"
  value = {
    oracle   = "cdc-oracle.${var.namespace}.svc.cluster.local:${var.oracle_port}"
    mssql    = "cdc-mssql.${var.namespace}.svc.cluster.local:${var.mssql_port}"
    postgres = "cdc-postgres.${var.namespace}.svc.cluster.local:${var.postgres_port}"
    mysql    = "cdc-mysql.${var.namespace}.svc.cluster.local:${var.mysql_port}"
  }
}

# 옛 docker 포트를 그대로 재현하는 명령이다 — DBeaver 같은 클라이언트의 접속 설정을 바꾸지 않아도 된다.
output "port_forward_commands" {
  description = "로컬 PC 에서 소스 RDB 에 붙는 방법 (docker 시절 포트 그대로)"
  value = {
    oracle   = "kubectl -n ${var.namespace} port-forward svc/cdc-oracle 11521:${var.oracle_port}"
    mssql    = "kubectl -n ${var.namespace} port-forward svc/cdc-mssql 11433:${var.mssql_port}"
    postgres = "kubectl -n ${var.namespace} port-forward svc/cdc-postgres 15432:${var.postgres_port}"
    mysql    = "kubectl -n ${var.namespace} port-forward svc/cdc-mysql 13306:${var.mysql_port}"
  }
}

# Oracle 만 계정이 둘이다(업무 스키마 · LogMiner 공통유저) — 커넥터 JSON 의 database.user 는 후자다.
output "cdc_source_accounts" {
  description = "커넥터 JSON 의 database.user 에 들어가는 계정 (비밀번호는 secrets.auto.tfvars)"
  value = {
    oracle   = var.oracle_dbz_user
    mssql    = "sa"
    postgres = var.postgres_user
    mysql    = var.mysql_user
  }
}
