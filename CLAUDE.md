# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 저장소 개요

kubeadm 3노드 랩 클러스터 위에 Terraform 스택을 레이어로 쌓는 IaC 저장소.
클러스터: ap=192.168.56.200(control-plane), s1=192.168.56.201, s2=192.168.56.202 — k8s v1.34.4, containerd.

## 아키텍처: 번호 디렉토리 = 독립 스택

숫자 접두사 디렉토리 하나가 독립된 Terraform 루트 모듈이며 **각자 자기 state를 가진다**.
번호 = 적용 순서. destroy 는 역순(002 → 001).

- `001-base` — local-path-provisioner. kubeadm 엔 기본 StorageClass 가 없어 이것 없이는 모든 PVC 가 Pending 에 걸린다. 다른 모든 스택의 선행 조건.
- `002-harbor` — Harbor 레지스트리 (공식 goharbor 차트, NodePort 30002, TLS 없는 HTTP). `externalURL` 은 실제 접속 주소와 반드시 일치해야 docker push 가 동작한다. HTTP 라서 push/pull 클라이언트에 insecure-registry 설정(docker `insecure-registries`, containerd `certs.d`)이 선행돼야 한다.
- `003-monitoring` — (예정) alloy + prometheus + grafana. 이미지는 사용자가 tar 로 빌드해 Harbor 에 push 한 것을 pull.

**스택 간 의존성은 코드에 없다.** 다른 state 의 리소스에 `depends_on` 을 걸 수 없으므로 순서는 디렉토리 번호 규칙이 담당하고, 스택 사이에 Terraform 이 모델링 못 하는 수동 단계(이미지 push)가 존재한다. 스택 간 값 전달은 `terraform output -raw <이름>` 으로 소비한다 (002-harbor/outputs.tf 가 공개 인터페이스).

## 명령어

스택마다 각자 init 부터. 루트에서 실행할 때는 `-chdir` 사용:

```bash
terraform -chdir=001-base init && terraform -chdir=001-base plan
terraform -chdir=002-harbor fmt -check     # 포맷 검사
terraform -chdir=002-harbor validate       # 문법 검증 (init 이후 가능)
```

**`terraform apply`/`destroy` 는 사용자가 직접 실행한다.** Claude 는 파일 작성과 plan/fmt 수준 검증까지만 하고, 실행 명령어를 안내로 제공할 것.

## 규칙 (이 저장소의 비자명한 결정들)

- **버전은 전부 정확 고정.** `>=`, `~>` 같은 범위 연산자 금지 — CLI(`required_version`), 프로바이더, Helm 차트 모두. 업그레이드는 버전 숫자를 고치는 커밋으로만 한다. 새 버전을 박기 전에 해당 레지스트리(registry.terraform.io, 차트 index.yaml)에서 실존 여부를 조회할 것. 차트는 갓 나온 라인(.0/.1)보다 패치가 쌓인 라인을 선호.
- **리소스가 없는 프로바이더는 선언하지 않는다.** kubernetes 프로바이더가 없는 것은 의도된 것 — `kubernetes_*` 리소스가 처음 생길 때 그 스택에만 추가한다 (helm 프로바이더는 자체적으로 kubeconfig 를 읽음).
- **환경마다 달라야 하는 변수는 default 를 주지 않는다** (예: `harbor_external_ip`) — tfvars 강제로 실수를 plan 단계에서 차단.
- Helm values 는 인라인 `yamlencode()` — 한 화면을 넘으면 별도 파일로 분리.
- 주석은 한국어, 섹션 구분은 `####` 배너 스타일.
- `.terraform.lock.hcl` 은 커밋, `*.tfstate` 는 절대 커밋 금지 (state 엔 sensitive 값이 평문으로 남는다 — .gitignore 가 막고 있음).
- 최소주의: 리소스/설정은 꼭 필요한 것만. remote backend, atomic, modules 등은 필요가 생기기 전까지 도입하지 않기로 결정됨.
