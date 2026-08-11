# 300-data-layer-base — Helm 차트

**Terraform 스택에서 Helm 차트로 전환된 첫 스택.** 워크로드·이미지 없이 공용 오브젝트 4개만
만든다 — 300번대 전 스택이 이걸 이름으로 참조하므로 번호가 300(맨 먼저)이고, 추후 ArgoCD
app-of-apps 에서는 sync-wave 0 이 이 순서를 대신 지킨다.

| 오브젝트 | 이름 | 소비 방식 |
|---|---|---|
| Namespace | `data-layer` | 전 스택의 배포 대상 (이 차트가 유일한 소유자) |
| ConfigMap | `data-layer-env` | 워크로드가 `envFrom.configMapRef` 로 통째로 주입 |
| Secret | `data-layer-secrets` | 워크로드가 `envFrom.secretRef` 로 통째로 주입 |
| ClusterRoleBinding | `data-layer-default-admin` | default SA → cluster-admin (저장소 유일의 권한 오브젝트) |

301~307 은 영향 없다 — 그 스택들은 이 디렉토리가 아니라 **클러스터의 ConfigMap** 을
`data` 소스로 읽으므로, 소유 도구가 Terraform → Helm 으로 바뀌어도 계약(오브젝트 이름·키)은 그대로다.

## values 계약

- `global.*` — 네임스페이스 + 클러스터 밖 접속값(Kafka·MinIO·PostgreSQL·Neo4j). 추후 ArgoCD
  app-of-apps 아래에서는 루트 values 가 주입한다(단독 helm 배포 동안은 이 파일이 단일 출처).
- 나머지 최상위 키 — 이 차트가 소유한 값(다른 스택 포트·호스트명 미러, DB 이름, `secrets`).
- `values.schema.json` 이 필수 키·형식(호스트명 밑줄 금지, host:port 형식 등)을 렌더 시점에
  강제한다 — 구 "환경 의존 변수는 default 없이 tfvars 강제" 규칙의 승계.
- 값 변경 = values 수정 → `helm upgrade`(추후에는 git push + argocd sync). kubectl 직접 수정 금지.

## 설치 (최초 1회)

구 Terraform 시절 오브젝트는 클러스터 재구축으로 남아 있지 않다 — 인수인계 절차 없이 그냥 설치한다.

release 기록을 `default` 에 두는 이유: helm 은 설치 기록(Secret)을 보관할 네임스페이스가
먼저 필요한데, `data-layer` 는 이 차트가 만들 대상이라 설치 시점엔 아직 없다.
`--create-namespace` 를 쓰면 helm 이 먼저 만든 네임스페이스와 차트 안의 Namespace 오브젝트가
"already exists" 로 충돌하므로 쓰지 않는다(네임스페이스 소유권은 차트에 있어야 한다).

```bash
helm template data-layer-base ./300-data-layer-base            # 미리보기 (클러스터 접근 없음)
helm install data-layer-base ./300-data-layer-base -n default

# 확인
helm -n default ls
kubectl -n data-layer get cm/data-layer-env secret/data-layer-secrets   # DATA 70 / 12
kubectl get clusterrolebinding data-layer-default-admin
```

⚠ `helm uninstall data-layer-base -n default` 는 **네임스페이스째** 지운다 — 301~307 워크로드가
올라간 뒤에는 그것까지 전부 사라진다. 값 변경은 재설치가 아니라 `helm upgrade` 로 한다.

## 일상 운영

```bash
helm lint 300-data-layer-base                                      # 문법 + 스키마 검사
helm template data-layer-base 300-data-layer-base                  # 렌더 확인 (클러스터 접근 없음)
helm template data-layer-base 300-data-layer-base | kubectl diff -f -   # 라이브와 대조
helm upgrade data-layer-base ./300-data-layer-base -n default      # 값 변경 반영
```

## 추후 ArgoCD

이 차트는 그대로 ArgoCD Application 의 `source.path` 가 될 수 있다(전체 설계·app-of-apps 는
`/my_project/test/README.md` 참조). helm 으로 배포 중인 상태에서 ArgoCD 로 넘어갈 때는
Argo 가 같은 매니페스트를 렌더하므로 오브젝트 충돌이 없고, 남는 helm release 메타데이터
(`sh.helm.release.v1.*` Secret)만 정리하면 된다.
