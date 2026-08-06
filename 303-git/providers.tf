# ===============================================
# [Kubernetes Provider]
#   → 클러스터 접속은 kubeconfig 하나로 일원화한다(control-plane admin.conf 복사본).
#   ⚠ kubernetes_manifest 는 plan 단계에서 API 서버에 스키마를 물어본다 —
#     클러스터가 닿지 않으면 plan 자체가 실패하는 것이 정상이다.
# ===============================================
provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}
