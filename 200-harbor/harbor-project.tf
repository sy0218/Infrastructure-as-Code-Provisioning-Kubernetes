# ===============================================
# [Harbor Project]
#
# → Harbor에 "data-layer" 프로젝트를 생성한다.
# → data-layer 관련 컨테이너 이미지를 이 프로젝트에 저장한다.
# → 이미지 주소: <Harbor 주소>/data-layer/<이미지명>
# → public = true: 인증 없이 이미지 Pull 가능
#
# → Harbor가 먼저 설치되어야 프로젝트를 생성할 수 있으므로
#    Helm Release 완료 후 생성되도록 의존성을 설정한다.
# ===============================================

resource "harbor_project" "data_layer" {
  name   = "data-layer"
  public = true

  # Harbor 설치 완료 후 프로젝트 생성
  # 그래야 Terraform이 Harbor에 접속해서 프로젝트를 만들 수 있다.
  depends_on = [helm_release.harbor]
}