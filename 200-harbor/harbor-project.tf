# ===============================================
# [Harbor 프로젝트]
# → Harbor 안에 "data-layer"라는 저장소 공간을 만든다.
# → data-layer 관련 Docker 이미지를 여기에 모아둔다.
# → 이미지 주소는 harbor.example.com/data-layer/이미지명 형태가 된다.
# → 폐쇄망 환경이라 외부 인증 없이 이미지를 pull할 수 있도록 public으로 설정한다.

# → Harbor를 먼저 설치해야 프로젝트를 만들 수 있다.
# → 따라서 Harbor Helm 설치가 끝난 뒤 이 프로젝트를 생성한다.

# ===============================================

resource "harbor_project" "data_layer" {
  name   = "data-layer"
  public = true

  # Harbor Helm 설치가 먼저 끝나야 한다.
  # 그래야 Terraform이 Harbor에 접속해서 프로젝트를 만들 수 있다.
  depends_on = [helm_release.harbor]
}