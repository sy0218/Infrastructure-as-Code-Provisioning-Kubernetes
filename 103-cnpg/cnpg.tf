# ===============================================
# [CloudNativePG Operator]
#   - CNPG = PostgreSQL을 자동으로 관리해주는 Kubernetes Operator
#   - 이 스택은 Operator와 CNPG CRD만 설치한다.
#   - PostgreSQL 자체는 이 스택에서 만들지 않는다.
#
# [전체 흐름]
#   1. 이 스택 → CNPG Operator + CRD 설치
#   2. 303-postgres → Cluster CR 생성
#   3. CNPG Operator → PostgreSQL 생성/복제/failover 등 관리
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

    # ===========================================
    # [Operator 이미지]
    #   - 실제로 실행되는 CNPG Operator 이미지
    #   - 노드는 Harbor에서 이미지를 가져온다.
    # ===========================================
    image = {
      repository = "${var.harbor_registry}/data-layer/cloudnative-pg"
      tag        = var.operator_image_tag
    }

    # CNPG가 사용하는 CRD(Cluster, Database, Pooler 등) 설치
    crds = {
      create = true
    }

    # ===========================================
    # [모니터링]
    #   - Prometheus/Grafana는 별도 monitoring 스택이 관리한다.
    #   - CNPG는 PodMonitor/Grafana Dashboard를 만들지 않는다.
    # ===========================================
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
