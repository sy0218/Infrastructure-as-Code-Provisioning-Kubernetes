# ===============================================
# [Harbor 프로젝트]
#   → data-layer 이미지 전체가 들어갈 프로젝트 — 주소 규약은 <harbor>/data-layer/<name>:<tag>.
#   → public = true 는 폐쇄망 랩이라 image pull 인증을 두지 않기 위함이다.
# ===============================================
resource "harbor_project" "data_layer" {
  name   = "data-layer"
  public = true

  # ⚠ 둘 다 필요하다. 파드가 떠 있는 것(helm)만으로는 부족하고, harbor 프로바이더가 쓰는
  #   주소(http://<harbor_host>)가 실제로 열려 있어야 하는데 그 경로를 여는 것이 Ingress 다.
  #   Ingress 를 빼면 첫 apply 에서 "dial tcp ...:80: connect: connection refused" 로 죽는다.
  depends_on = [
    helm_release.harbor,
    kubernetes_manifest.harbor_ingress,
  ]
}
