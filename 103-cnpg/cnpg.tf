# ===============================================
# [CloudNativePG Operator]
#   - Kubernetes에서 PostgreSQL 클러스터를 자동으로 운영하기 위한
#   - CloudNativePG(CNPG) Operator를 설치한다.
#
# 이 스택에서는 "PostgreSQL 서버"를 직접 생성하지 않는다.
# Operator와 CRD만 설치하고,
# 실제 PostgreSQL 클러스터는 별도의 303-postgres 스택에서 생성한다.
#
# [구성 흐름]
#
#   1. 이 스택
#      └─ CNPG Operator 설치
#      └─ CNPG CRD 설치
#
#   2. 303-postgres
#      └─ CNPG Cluster 리소스 생성
#
#   3. CNPG Operator
#      └─ Cluster 리소스를 감시
#      └─ PostgreSQL Pod 생성
#      └─ 복제/Failover 등 PostgreSQL 운영 관리
#
# 즉,
#   Terraform/Helm → Operator 설치
#   Kubernetes CR  → PostgreSQL 클러스터 선언
#   CNPG Operator  → 실제 PostgreSQL 운영
# ===============================================

resource "helm_release" "cloudnative_pg" {
  name             = "cloudnative-pg"
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  version          = var.cnpg_chart_version
  namespace        = var.namespace
  create_namespace = true
  timeout          = 600

  values = [yamlencode({
    # CNPG가 사용하는 CRD(Cluster, Database, Pooler 등) 설치
    crds = {
      create = true
    }

    # -------------------------------------------
    # [모니터링]
    #   - 모니터링은 monitoring 스택이 관리한다.
    #   - CNPG는 PodMonitor/Grafana Dashboard를 만들지 않는다.
    # -------------------------------------------
    monitoring = {
      podMonitorEnabled = false
      grafanaDashboard = {
        create = false
      }
    }

    # Operator Pod의 리소스 요청
    resources = {
      requests = {
        cpu    = "50m"
        memory = "128Mi"
      }
    }
  })]
}
