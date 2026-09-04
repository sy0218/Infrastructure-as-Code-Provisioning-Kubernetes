# 303-postgres — Helm 차트

**플랫폼 PostgreSQL.** CloudNativePG(CNPG) Cluster 1개(인스턴스 2 — primary 1 + replica 1, values `instances`·`nodeNames`)로
메타 DB 3종(`airflow` / `data_layer` / `iceberg_catalog`)을 담는다.
오퍼레이터·CRD 는 103-cnpg 가, 외부 VIP 대역은 102-ingress 가 소유하고, 이 차트는 선언(CR)만 소유한다.
추후 ArgoCD app-of-apps 에서는 sync-wave 1 (300 다음, 304 이전)이다.

| 오브젝트 | 이름 | 역할 |
|---|---|---|
| Cluster (CNPG) | `data-layer-postgres` | PostgreSQL 16.15 + TimescaleDB 2.29.0, 인스턴스 2(s1·s2), 노드 강제 분산 |
| Database (CNPG) | `data-layer-postgres-airflow` / `-iceberg-catalog` | `airflow` · `iceberg_catalog` DB 선언 (구 initdb.d/02 + POSTGRES_DB 승계) |
| Secret | `data-layer-postgres-app-user` | 앱 계정(basic-auth) — CNPG 가 role 생성·비밀번호 동기화에 사용 |
| Service | `data-layer-postgres-metrics` | 302-monitoring 스크랩용 (인스턴스 2개 전부, :9187) |
| Service | `data-layer-postgres-external` | 외부 접속용 LoadBalancer — MetalLB VIP `192.168.56.241:5432` |
| (오퍼레이터 생성) | `-rw` / `-ro` / `-r` Service, 파드 `-1..-2`, PVC, 인스턴스 SA/Role | 쓰기(primary) / 읽기(replica) / 전체 진입점 등 |

앱 DB(`data_layer`)와 스키마·테이블(`collect_job`·`realtime_source`·`data_lineage` 하이퍼테이블)은
Cluster 의 `bootstrap.initdb` + `postInitApplicationSQL` 이 빈 볼륨 최초 부트스트랩 1회에 만든다 —
구 `data_pipeline/data_layer_postgres/initdb.d/` 3종의 승계이며, **CNPG 는
`/docker-entrypoint-initdb.d/` 를 실행하지 않으므로** 그 스크립트 파일들은 참고 문서로만 남았다.

## values 계약

- `global.*` 은 **이 차트에 없다** — 저장소 루트 `values.common.yaml` 이 유일한 정의처다(`-f values.common.yaml`).
  여기서 쓰는 것은 `namespace` · `harborRegistry` · `postgres.*`(clusterName·port·schema·databases) ·
  `secrets.postgresUser` 다.
- **`postgres.*` 가 공통값인 이유**: 300 이 같은 값으로 접속 문자열(`COLLECTOR_DB_*`·`PLATFORM_PG_DSN`·
  `ICEBERG_CATALOG_URI`)을 조립한다. 클러스터 이름 하나에서 `<clusterName>-rw.<ns>.svc.cluster.local` 이
  파생되므로 주소 복사본이 없다.
- 나머지 최상위 키 — 이 차트가 소유한 값(`instances`·`nodeNames`·`imageTag`·`storage`·`externalIp`).
  **`imageTag`(`16.15-v0.1.1`)는 `global.imageTag` 를 쓰지 않는 유일한 값이다** — CNPG 웹훅이 태그에서 PG 메이저를 읽어
  `v0.1.0` 은 "invalid version tag" 로 거부된다. 앞자리는 이미지의 실제 PG 버전, 뒷자리는 `build_and_push.sh` 에 준 태그다.
- `values.schema.json` 이 필수 키·형식을 렌더 시점에 강제한다.

### 이 차트가 만들지 않는 것

- **Secret `<clusterName>-app-user`** (CNPG 가 role 생성·비밀번호 관리에 쓰는 입력) — 300-data-layer-base 가 만든다.
  인증 정보의 소유자가 그 차트이기 때문이다. 별도 오브젝트인 이유는 CNPG 가 `kubernetes.io/basic-auth` 타입의
  `username`/`password` 키를 요구해서다(공용 `data-layer-secrets` 는 Opaque 라 그대로 못 쓴다).
  값은 같은 `global.secrets` 에서 오므로 두 곳이 어긋날 수 없다.

### 클러스터 밖 값과의 커플링 (바꿀 때 같은 커밋에서 함께)

- `global.postgres.clusterName` → 302-monitoring `prometheus-config.yaml` 의 keep regex
  (`data-layer-postgres-metrics;metrics`)와 304 의 `postgres_host` 가 이 이름에서 나온다.
  (300 의 접속 호스트는 복사본이 아니라 같은 값에서 파생된다.)
- `externalIp` → 102-ingress 의 `postgres_vip` (IPAddressPool `postgres-vip`)와 같은 값.

### 규칙 예외 2건 (문서화된 의도)

1. **오퍼레이터가 클러스터별 ServiceAccount/Role/RoleBinding 을 `data-layer` 에 자동 생성한다** —
   '권한 오브젝트는 300 의 ClusterRoleBinding 하나' 규칙의 예외다. 우리가 만드는 것이 아니라
   오퍼레이터 소유물이고, 지우면 인스턴스가 API 서버를 못 불러 클러스터가 멈춘다.
2. **`enableServiceLinks: false` 를 넣을 수 없다** — 파드 템플릿을 오퍼레이터가 소유한다
   (CNPG 1.30 에 해당 필드 없음, upstream issue #6234). CNPG 엔트리포인트는 Service env 를
   읽지 않아 실피해는 없다.

### 계정 권한 — superuser 를 끊었다

구 Ansible 롤은 `data_layer` 를 SUPERUSER 로 만들었지만, 여기서는 **owner 권한만** 준다
(`managed.roles` 의 `superuser: false`). 3개 DB 전부 이 계정이 owner 라 Airflow `db migrate`·
pyiceberg 자체 DDL·`create_hypertable` 모두 통과하고, superuser 가 필요한 `CREATE EXTENSION` 은
부트스트랩이 미리 해 둔다(`IF NOT EXISTS` 는 NOTICE 로 끝난다). 임시 관리 작업은
`kubectl -n data-layer exec -it data-layer-postgres-1 -c postgres -- psql -U postgres` (local peer).

## 설치

전제: **103-cnpg apply 완료**(CRD — 없으면 install 이 "no matches for kind Cluster" 로 죽는다.
`helm template` 은 CRD 검증을 안 해 통과한다), 300-data-layer-base 설치 완료(네임스페이스),
이미지 `postgres` 가 values `imageTag` 와 같은 태그로 Harbor 에 push 되어 있을 것
(`/project/data_pipeline/scripts/build_and_push.sh 16.15-v0.1.1 postgres` — 오퍼레이터 이미지는 103-cnpg 가 차트 기본 ghcr.io 를 쓴다),
외부 VIP 는 102-ingress 의 `postgres-vip` 풀 필요.

release 를 `data-layer` 에 두는 이유: 네임스페이스가 이미 있고, 이 차트의 오브젝트 전부가
그 안에 있다 — 기록과 실체를 한곳에 둔다.

```bash
helm lint 303-postgres -f values.common.yaml                                  # 문법 + 스키마 검사
helm template postgres ./303-postgres -f values.common.yaml                   # 미리보기 (클러스터 접근 없음)
helm install postgres ./303-postgres -f values.common.yaml -n data-layer

# 확인
helm -n data-layer ls
kubectl -n data-layer get cluster data-layer-postgres              # "Cluster in healthy state", READY 2
kubectl -n data-layer get pods -l cnpg.io/cluster=data-layer-postgres -o wide   # s1·s2 에 분산
kubectl -n data-layer get database                                 # airflow / iceberg_catalog reconciled
kubectl -n data-layer get svc | grep data-layer-postgres           # -rw/-ro/-r/-metrics/-external(EXTERNAL-IP .241)
kubectl -n data-layer exec data-layer-postgres-1 -c postgres -- \
  psql -U postgres -c "SELECT application_name, state, sync_state FROM pg_stat_replication;"   # replica 1줄 streaming
kubectl -n data-layer exec data-layer-postgres-1 -c postgres -- \
  psql -U postgres -d data_layer -c "\dt data_pipeline.*"          # collect_job/realtime_source/data_lineage
```

## 일상 운영

```bash
helm lint 303-postgres -f values.common.yaml                                       # 문법 + 스키마 검사
helm template postgres 303-postgres -f values.common.yaml                          # 렌더 확인 (클러스터 접근 없음)
helm template postgres 303-postgres -f values.common.yaml | kubectl diff -f -      # 라이브와 대조
helm upgrade postgres ./303-postgres -f values.common.yaml -n data-layer           # 값 변경 반영 (오퍼레이터가 롤링 수행)
# helm uninstall 은 신중히 — Cluster CR 삭제 = 오퍼레이터가 파드·PVC 까지 삭제(데이터 소실)

# failover 스모크 테스트 — primary 를 지워 승격을 본다
kubectl -n data-layer get pods -l cnpg.io/instanceRole=primary
kubectl -n data-layer delete pod <현재 primary>
kubectl -n data-layer get cluster data-layer-postgres -w     # Failing over → healthy 복귀 관찰

# 사람 접속 — 클러스터 밖에서는 VIP, 안에서는 Service DNS
psql "host=192.168.56.241 port=5432 dbname=data_layer user=data_layer"
```

- `instances`·`resources` 변경은 `helm upgrade` 로 안전하다(오퍼레이터가 수렴).
  **`storage.storageClass` 는 첫 install 후 변경 불가**(PVC 불변) — 바꾸려면 재부트스트랩이다.
- 이미지 태그 변경(values `imageTag`) = PostgreSQL/TimescaleDB 업그레이드 — replica 부터 갈고
  primary 는 자동 switchover(`primaryUpdateStrategy: unsupervised`). 확장 버전이 움직이면
  `ALTER EXTENSION timescaledb UPDATE` 를 superuser 로 별도 실행해야 한다.
- 백업/PITR 은 이 차트 범위 밖이다 — **향후 과제**: CNPG barman 플러그인 + 객체 스토리지(MinIO)
  예약 백업. 레플리카는 장비 장애만 막지, 잘못된 DELETE 는 두 인스턴스에 그대로 복제된다.

## 추후 ArgoCD

이 차트는 그대로 ArgoCD Application 의 `source.path` 가 될 수 있다. `global.*` 는 app-of-apps
루트 values 가 주입하고, sync-wave 1 (300 다음, 304 이전)로 지금의 번호 순서를 대체한다.
