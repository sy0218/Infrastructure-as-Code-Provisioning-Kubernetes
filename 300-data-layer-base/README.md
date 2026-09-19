# 300-data-layer-base — Helm 차트

**공용 오브젝트의 소유자.** 워크로드·이미지 없이 네임스페이스·공용 환경변수·인증정보·권한 바인딩을 만든다 —
300번대 전 스택이 이걸 이름으로 참조하므로 번호가 300(맨 먼저)이고, 추후 ArgoCD app-of-apps 에서는
sync-wave 0 이 이 순서를 대신 지킨다.

| 오브젝트 | 이름 | 소비 방식 |
|---|---|---|
| Namespace | `data-layer` | 전 스택의 배포 대상 (이 차트가 유일한 소유자) |
| ConfigMap | `data-layer-env` | 워크로드가 `envFrom.configMapRef` 로 통째로 주입 (환경변수) |
| Secret | `data-layer-secrets` | 워크로드가 `envFrom.secretRef` 로 통째로 주입 (Opaque) |
| Secret | `<postgres.clusterName>-app-user` | 303 CNPG 가 role 생성에 사용, 305-api 가 `COLLECTOR_DB_USER/PASSWORD` 로 `secretKeyRef` (basic-auth — 앱 계정의 유일한 원본) |
| ClusterRoleBinding | `data-layer-default-admin` | default SA → cluster-admin (저장소 유일의 권한 오브젝트) |

**설정 ConfigMap 은 이 차트가 소유하지 않는다.** 301-kafka 의 `kafka-config`·`kafka-jmx-exporter`, 302-monitoring 의 `alloy-config`·
`prometheus-config`·`grafana-datasource` 는 그것을 읽는 차트가 소유한다 — 설정과 파드가 **같은 릴리스**여야 파드 템플릿에
`checksum/*` 을 심을 수 있기 때문이다(302 는 `helm upgrade` 만으로 롤아웃, 301 브로커는 OnDelete 라 사람이 재기동).
이 차트의 ConfigMap 은 `data-layer-env` 하나이고, 그 값을 바꾸면 읽는 워크로드(다른 릴리스)는 사람이 재기동한다.

301~307 은 오브젝트 이름으로 참조하므로 소유 차트가 바뀌어도 계약(이름·키)은 그대로다.

## values 계약

- `global.*` 은 **이 차트에 없다** — 저장소 루트 `values.common.yaml` 이 유일한 정의처이고
  300번대 차트가 전부 `-f values.common.yaml` 로 같은 파일을 먹는다. 안 주면 스키마가 렌더 전에 막는다.
- 이 차트만 쓰는 값은 없다 — values.yaml 자체가 없고 전부 global 에서 온다(helm 은 values.yaml 없는 차트를 허용한다).
- **접속 주소는 값이 아니라 파생값이다** — `templates/_helpers.tpl` 이 조립한다:
  `KAFKA_BOOTSTRAP` ← `global.kafka.brokers` × `global.kafka.ports.client` (노드 IP 직결),
  `COLLECTOR_DB_HOST` ← `global.postgres.clusterName`, `ICEBERG_WAREHOUSE` ← `global.hadoop.nameservice`
  (301-hadoop 의 fs.defaultFS 와 같은 원본). 주소 문자열을 values 에 적어 두지 않으므로
  301·303 과 어긋날 방법이 없다(구 "같은 커밋 규칙" 이 필요 없어졌다).
- **공용 키는 '읽는 이름'당 하나다.** 같은 값을 다른 이름으로 읽는 워크로드(lineage·tcp-socket 의 `*_PG_DSN`,
  tcp-socket 의 `TCP_SOCKET_DLQ_TOPIC`, Grafana 의 `GF_SERVER_ROOT_URL`, MinIO 서버의 `MINIO_ROOT_*`, 305 의 `COLLECTOR_DB_USER/PASSWORD`)는
  여기 사본 키를 늘리지 않고 자기 차트의 `env:` 에서 `valueFrom` 으로 번역한다 — 300 을 바꿀 때 사본이 어긋날 방법이 없다.
  같은 이유로 사본 키를 지울 때는 **소비 차트를 먼저 upgrade 하고 300 을 나중에** 한다.
- `values.schema.json` 이 이 차트가 참조하는 global 키만 required 로 선언한다 — 구 "환경 의존 변수는
  default 없이 tfvars 강제" 규칙의 승계.
- 값 변경 = values 수정 → `helm upgrade`(추후에는 git push + argocd sync). kubectl 직접 수정 금지.

## 설치 (최초 1회)

구 Terraform 시절 오브젝트는 클러스터 재구축으로 남아 있지 않다 — 인수인계 절차 없이 그냥 설치한다.

release 기록을 `default` 에 두는 이유: helm 은 설치 기록(Secret)을 보관할 네임스페이스가
먼저 필요한데, `data-layer` 는 이 차트가 만들 대상이라 설치 시점엔 아직 없다.
`--create-namespace` 를 쓰면 helm 이 먼저 만든 네임스페이스와 차트 안의 Namespace 오브젝트가
"already exists" 로 충돌하므로 쓰지 않는다(네임스페이스 소유권은 차트에 있어야 한다).

```bash
helm template data-layer-base ./300-data-layer-base -f values.common.yaml            # 미리보기 (클러스터 접근 없음)
helm install data-layer-base ./300-data-layer-base -f values.common.yaml -n default

# 확인
helm -n default ls
kubectl -n data-layer get cm/data-layer-env secret/data-layer-secrets   # DATA 63 / 8
kubectl get clusterrolebinding data-layer-default-admin
```

⚠ `helm uninstall data-layer-base -n default` 는 **네임스페이스째** 지운다 — 301~307 워크로드가
올라간 뒤에는 그것까지 전부 사라진다. 값 변경은 재설치가 아니라 `helm upgrade` 로 한다.

## 일상 운영

```bash
helm lint 300-data-layer-base -f values.common.yaml                                      # 문법 + 스키마 검사
helm template data-layer-base 300-data-layer-base -f values.common.yaml                  # 렌더 확인 (클러스터 접근 없음)
helm template data-layer-base 300-data-layer-base -f values.common.yaml | kubectl diff -f -   # 라이브와 대조
helm upgrade data-layer-base ./300-data-layer-base -f values.common.yaml -n default      # 값 변경 반영
```

## 추후 ArgoCD

이 차트는 그대로 ArgoCD Application 의 `source.path` 가 될 수 있다(전체 설계·app-of-apps 는
`/my_project/test/README.md` 참조). helm 으로 배포 중인 상태에서 ArgoCD 로 넘어갈 때는
Argo 가 같은 매니페스트를 렌더하므로 오브젝트 충돌이 없고, 남는 helm release 메타데이터
(`sh.helm.release.v1.*` Secret)만 정리하면 된다.
