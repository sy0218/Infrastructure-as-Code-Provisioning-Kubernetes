# 307-pipeline — Helm 차트

**CDM 파이프라인 워커.** 전부 PVC 없는 Deployment 이고 리슨 포트가 없어 probe 도 없다(이상 감지 = 컨슈머 그룹 lag).

| 오브젝트 | 이름 | 역할 |
|---|---|---|
| Deployment ×8 | `cdm-mapper-<모듈>` | `raw.*` → CDM → `cdm-topic`. 이미지 하나 + 모듈별 `command`. 라벨 `app=cdm-mapper`,`cdm.mapper/module=<모듈>` 은 **305-api DQ 적용과의 계약** |
| Deployment ×3 | `cdm-consumer-{rdb,graph,warehouse}` | `cdm-topic` → PostgreSQL / Neo4j / Iceberg. 이름 = 라벨 app = 컨슈머 그룹 |
| Deployment | `cdm-lineage-consumer` | `lineage-topic` → PostgreSQL(계보). 본 경로와 분리돼 계보 DB 장애가 파이프라인을 멈추지 않는다 |
| Deployment | `tcp-socket-collector` | 장비 push → `raw.*`. **hostNetwork + nodeSelector**(저장소 유일) — 리슨 포트가 런타임 DB 값이라 Service 가 없다 |

## values 계약

- `global.*` 은 이 차트에 없다 — 루트 `values.common.yaml` 이 정의처다(`-f values.common.yaml`).
  쓰는 것: `namespace` · `harborRegistry` · `imageTag`. 토픽·배치·로그레벨 등 실행 설정은 300 의 공용 ConfigMap 이다.
- `mapper.modules` 한 줄 = Deployment 하나. 모듈명(스네이크)은 `data_layer_mappers/<모듈>.py` 와 1:1 이고
  오브젝트 이름은 케밥(`cdm-mapper-qm-chemical-batches`). 목록에서 빼면 `helm upgrade` 가 지운다.
- `mapper.terminationGracePeriodSeconds`(200) > 300 의 `DATA_QUALITY_RESTART_DRAIN_TIMEOUT`(180) 이어야 한다 —
  305-api `ingress.proxyReadTimeout` 까지 한 사슬이다.
- `consumer.kinds.<종류>.fromConfigMap / fromSecret` 은 '코드가 읽는 이름 → 공용 오브젝트 키' 번역표다.
  이름이 같은 값은 envFrom 으로 들어오므로 적지 않는다(rdb 는 번역할 것이 없다).
- `replicas` 상한은 토픽 파티션 수(3) — 그 이상은 파티션을 못 받아 유휴다.
- **`tcpSocket.nodeSelector` 의 노드 라벨은 차트가 붙이지 않는다**(Node 는 클러스터 오브젝트 — Helm 소유 부적합).
  구 Terraform 의 `kubernetes_labels` 는 수동 단계로 돌아갔다: `kubectl label node s2 ingest=true`.
  ⚠ 장비가 실제로 패킷을 보내는 노드여야 한다 — 틀리면 Running 인데 아무것도 받지 않는다.
- **`resources.requests` 는 당분간 주석 처리** — 304-airflow 와 같은 임시 조치. 여유가 생기면 푼다.

## 설치

전제: 300 · 301-kafka · 301-minio · 303-postgres 설치 완료, Harbor 에 이미지 6종
(`cdm-mapper` · `cdm-consumer-rdb/graph/warehouse` · `cdm-lineage-consumer` · `tcp-socket-collector`) push 완료,
ingest 노드 라벨 완료.

```bash
kubectl label node s2 ingest=true                                   # 장비가 보내는 노드 (한 번)

helm lint 307-pipeline -f values.common.yaml
helm template pipeline ./307-pipeline -f values.common.yaml
helm install pipeline ./307-pipeline -f values.common.yaml -n data-layer

kubectl -n data-layer get pod -l app=cdm-mapper -L cdm.mapper/module
kubectl -n data-layer get pod -l 'app in (cdm-consumer-rdb,cdm-consumer-graph,cdm-consumer-warehouse,cdm-lineage-consumer,tcp-socket-collector)' -o wide
```
