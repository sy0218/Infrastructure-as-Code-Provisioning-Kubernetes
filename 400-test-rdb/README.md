# 400-test-rdb — Helm 차트

**CDC 소스 RDB 4종.** 파이프라인(300번대)의 입력을 흉내 내는 **테스트 픽스처**라 번호가 400 이다 —
300번대는 이 차트 없이 완결되고, 이 차트는 300번대의 어떤 오브젝트도 참조하지 않는다(공용 ConfigMap/Secret 도 쓰지 않는다).
스키마·계정·CDC 활성화가 곧 커넥터의 전제조건이라 **초기화 스크립트(`files/`)가 이 차트의 본체**다.

| DB | 오브젝트 | CDC 방식 | 초기화 |
|---|---|---|---|
| `cdc-oracle` | ConfigMap + STS + Service | LogMiner — c## 공통유저 + 보충로깅 + LOGMINER_TBS | 이미지 훅 `/container-entrypoint-initdb.d`(`.sh`, 0755 — env 로 비밀번호를 받는다) |
| `cdc-mssql` | ConfigMap + STS + Service + **Job** | 네이티브 CDC — SQL Agent 잡이 캡처 | **helm hook Job**(post-install/upgrade, IF NOT EXISTS 라 멱등) — 이미지에 훅이 없다 |
| `cdc-postgres` | ConfigMap + STS + Service | 논리복제 pgoutput — publication 을 미리 만든다 | 이미지 훅 `/docker-entrypoint-initdb.d` |
| `cdc-mysql` | ConfigMap + STS + Service | binlog ROW/FULL — 전역 복제 권한을 initdb 가 준다 | 이미지 훅 `/docker-entrypoint-initdb.d` |
| 공통 | Secret `test-rdb-secrets` | 넷이 비밀번호 하나를 공유(커넥터 JSON 의 `${CDC_SOURCE_DB_PASSWORD}` 자리) | — |

## values 계약

- `global.*` 은 `namespace` · `harborRegistry` · `imageTag` 만 쓴다(`-f values.common.yaml`).
- **Service 이름 + 포트 + 계정/DB 이름이 대외 계약이다** — `data_layer_debezium/connect_json/*.json` 의
  `database.hostname/user/dbname` 과 Airflow 커넥션 `cdc_oracle/mssql/postgres/mysql` 이 이 값과 같아야 한다.
  values 의 각 키 옆 주석이 어느 커넥터 필드와 짝인지 적어 두었다.
- `secrets.cdcSourceDbPassword` 는 `data_pipeline/.env` 의 `CDC_SOURCE_DB_PASSWORD` 와 같아야 한다(구 `secrets.auto.tfvars`).
- `storageClass` 는 `local-path` 다(저장소 규약의 명시적 예외) — 데이터는 `cdc_seed_loader` DAG 가 매일 01시 다시 채우므로
  Longhorn 복제(오라클만 ~12G)를 쓸 이유가 없다. longhorn 으로 바꾸면 STS 의 `fsGroup` 이 그때 의미를 갖는다.
- 초기화 스크립트는 `files/*-initdb.*` 에 두고 ConfigMap 이 `tpl` 로 values 를 치환한다.
  ⚠ oracle/postgres/mysql 은 **빈 볼륨 첫 기동에만** 돈다 — 고쳐도 롤아웃으로 반영되지 않고 PVC(`data-cdc-<db>-0`)를 지워야 한다.
  mssql 만 Job 이라 `helm upgrade` 마다 다시 돈다.
- `oracle.sgaTarget/pgaAggregateTarget` 은 Free 에디션 2GB 상한 안의 값이다 — 파드가 메모리로 못 뜨면 가장 먼저 낮춘다(1024M/256M 확인됨).
- **`resources.requests` 는 당분간 주석 처리** — 304-airflow 와 같은 임시 조치. 여유가 생기면 푼다.
- 외부 노출 없음(ClusterIP 뿐). 사람은 `kubectl port-forward` 로 docker 시절 포트를 재현한다(NOTES 참조).

## Terraform 에서 사라진 것

| 구 장치 | Helm 판 |
|---|---|
| mssql Job 이름의 SQL 해시(불변 spec 우회) | `helm.sh/hook-delete-policy: before-hook-creation` |
| `computed_fields` / `depends_on` | 불필요 — kind 순서(ConfigMap·Secret → STS → hook Job) |
| `defaultMode: 0o755`(YAML 1.2) | `0755` — Helm/kubectl 은 YAML 1.1 이라 8진수로 읽는다 |
| `$${VAR}` 이스케이프 | `${VAR}` 그대로 (Go 템플릿은 `$` 를 건드리지 않는다) |
| `outputs.tf` | `templates/NOTES.txt` |

## 설치

전제: 300-data-layer-base(네임스페이스) 설치 완료, Harbor 에 `test-rdb-{oracle,mssql,postgres,mysql}:<global.imageTag>` push 완료.

```bash
helm lint 400-test-rdb -f values.common.yaml
helm template test-rdb ./400-test-rdb -f values.common.yaml
# mssql 초기화 Job(hook) 완료까지 기다린다 — 첫 기동은 이미지 pull + 서버 기동에 수 분
helm install test-rdb ./400-test-rdb -f values.common.yaml -n data-layer --timeout 20m

kubectl -n data-layer get sts,pod,pvc,svc -l app.kubernetes.io/component=test-rdb
kubectl -n data-layer logs job/cdc-mssql-init                  # is_cdc_enabled=1
kubectl -n data-layer logs cdc-oracle-0 | grep '초기화 완료'     # 최대 15분
```

⚠ 넷을 한꺼번에 올리면 이미지 4종(오라클만 수 GB) pull 이 겹친다 — 느린 랩에서는 startupProbe 예산 안에 든다.
