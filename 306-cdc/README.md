# 306-cdc — Helm 차트

**Kafka Connect(Debezium).** 소스 RDB 4종(400-test-rdb)의 변경로그를 `raw.*` 토픽으로 흘리는 워커 묶음.
상태(커넥터 설정·오프셋·상태)는 전부 Kafka 내부 토픽이라 파드에 디스크도 고정 ID 도 없다 → Deployment ×N.

| 오브젝트 | 이름 | 역할 |
|---|---|---|
| Deployment | `cdc-connect` | 워커 `replicas` 개. podIP 를 광고해 비리더가 리더로 포워딩한다 |
| Service | `cdc-connect` | REST(`global.kafka.connectPort`) — **이름·포트가 300 의 `KAFKA_CONNECT_URL` 과 계약** |

## values 계약

- `global.*` 은 이 차트에 없다 — 루트 `values.common.yaml` 이 정의처다(`-f values.common.yaml`).
  쓰는 것: `namespace` · `harborRegistry` · `imageTag` · `kafka.connectPort`.
- 브로커 주소는 values 로 복사하지 않는다 — 공용 ConfigMap 의 `KAFKA_BOOTSTRAP` 을 `configMapKeyRef` 로 읽는다.
  ⚠ 파드를 다시 만들기 전엔 갱신되지 않는다 → 브로커 표가 바뀌면 300 upgrade 후 `rollout restart`.
- `storageTopics` 3종이 Connect 의 유일한 상태 저장소다. 이름을 바꾸면 커넥터가 사라진 것처럼 보이거나(config)
  스냅샷을 다시 뜬다(offset). `replicationFactor` 는 브로커 수(3) 이하여야 한다.
- `replicas` 는 임시로 2 다(원래 3) — 노드 메모리 여유가 없다. `heapOpts` 가 없으면 스크립트가 `-Xmx2G` 를 박는다.
- **`resources.requests` 는 당분간 주석 처리** — 304-airflow 와 같은 임시 조치. 여유가 생기면 푼다.
- 커넥터 등록 JSON(`data_layer_debezium/connect_json/*.json`)은 차트에 없다 — 관리 화면 '수집 › CDC 등록'
  또는 REST 로 사람이 넣는다. 소스 DB 비밀번호는 400-test-rdb 의 `secrets.cdcSourceDbPassword`.

## 설치

전제: 300-data-layer-base · 301-kafka 설치 완료, Harbor 에 `kafka-connect:<global.imageTag>` push 완료.

```bash
helm lint 306-cdc -f values.common.yaml
helm template cdc ./306-cdc -f values.common.yaml
helm install cdc ./306-cdc -f values.common.yaml -n data-layer

kubectl -n data-layer get deploy,pod,svc -l app=cdc-connect          # 첫 Ready 까지 수 분 (플러그인 스캔)
kubectl -n data-layer exec deploy/cdc-connect -- curl -s localhost:8083/connectors
```
