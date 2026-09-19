# 307-pipeline — Helm 차트

**CDM 파이프라인 워커.** 전부 PVC 없는 Deployment 이고 리슨 포트가 없어 probe 도 없다(이상 감지 = 컨슈머 그룹 lag).

| 오브젝트 | 이름 | 역할 |
|---|---|---|
| Deployment ×8 | `cdm-mapper-<모듈>` | `raw.*` → CDM → `cdm-topic`. 이미지 하나 + 모듈별 `command`. 라벨 `app=cdm-mapper`,`cdm.mapper/module=<모듈>` 은 **305-api DQ 적용과의 계약** |
| Deployment ×3 | `cdm-consumer-{rdb,graph,warehouse}` | `cdm-topic` → PostgreSQL / Neo4j / Iceberg. 이름 = 라벨 app = 컨슈머 그룹 |
| Deployment | `cdm-lineage-consumer` | `lineage-topic` → PostgreSQL(계보). 본 경로와 분리돼 계보 DB 장애가 파이프라인을 멈추지 않는다 |
| Deployment | `tcp-socket-collector` | 장비 push → `raw.*`. **hostNetwork + nodeAffinity**(`tcpSocket.nodeNames`) — 리슨 포트가 런타임 DB 값이라 Service 가 없다 |
| ConfigMap | `hdfs-client-config` | warehouse 컨슈머가 `/etc/hadoop/conf` 로 마운트하는 `core-site.xml`/`hdfs-site.xml` — `global.hadoop`(nameservice · namenode.nodeNames × nodes 표 · ports.namenodeRpc) 파생. 같은 릴리스라 파드 템플릿의 `checksum/hdfs-client` 로 `helm upgrade` 만으로 롤아웃 |

## values 계약

- `global.*` 은 이 차트에 없다 — 루트 `values.common.yaml` 이 정의처다(`-f values.common.yaml`).
  쓰는 것: `namespace` · `harborRegistry` · `imageTag` · `hadoop.nameservice` · `hadoop.namenode.nodeNames` · `hadoop.ports.namenodeRpc` ·
  `hadoop.warehouse.user` · `nodes`(hadoop.* 은 301-hadoop 서버 설정과 같은 원본 — 클라이언트 설정은 복사본이 아니라 파생값이다).
  토픽·배치·로그레벨 등 실행 설정은 300 의 공용 ConfigMap 이다.
- `mapper.modules` 한 줄 = Deployment 하나. 모듈명(스네이크)은 `data_layer_mappers/<모듈>.py` 와 1:1 이고
  오브젝트 이름은 케밥(`cdm-mapper-qm-chemical-batches`). 목록에서 빼면 `helm upgrade` 가 지운다.
- `mapper.terminationGracePeriodSeconds`(300) 는 helm upgrade·노드 drain 때 배치 드레인 상한이다. DQ 적용 재기동은 이 값을 쓰지 않는다 —
  305-api 가 파드 삭제 요청에 300 의 `DATA_QUALITY_RESTART_DRAIN_TIMEOUT`(180)을 직접 실어 보내고, 그 180 + 재기동 대기 60 = 240 이
  305-api `ingress.proxyReadTimeout`(300) 안에 들어야 한다 — 그 둘이 사슬이다.
- `consumer.kinds.<종류>.fromConfigMap / fromSecret` 은 '코드가 읽는 이름 → 공용 오브젝트 키' 번역표다.
  이름이 같은 값은 envFrom 으로 들어오므로 적지 않는다(rdb 는 번역할 것이 없다).
  lineage·tcp-socket 은 종류가 하나라 번역표가 values 가 아니라 템플릿 `env:` 에 있다 — `LINEAGE_PG_DSN`·`TCP_SOCKET_PG_DSN` ← `PLATFORM_PG_DSN`,
  `TCP_SOCKET_DLQ_TOPIC` ← `DATA_QUALITY_DLQ_TOPIC`(300 에 사본 키를 두지 않는다 — 300 README '공용 키는 읽는 이름당 하나').
- `consumer.kinds.<종류>.hdfs: true` 는 `hdfs-client-config` 를 `/etc/hadoop/conf`(이미지 `HADOOP_CONF_DIR`)에 마운트하고
  `HADOOP_USER_NAME`(= `global.hadoop.warehouse.user`) · `HADOOP_CONF_DIR` env 를 켠다 — 데이터 파일을 HDFS 에 쓰는 warehouse 만.
- `replicas` 상한은 토픽 파티션 수(3) — 그 이상은 파티션을 못 받아 유휴다.
- **`tcpSocket.nodeNames` 는 수집기를 띄울 노드 후보다**(302 prometheus/grafana 와 같은 nodeAffinity 패턴 — 노드 라벨 수동 단계 없음).
  이름은 `global.nodes` 표로 검증한다(없으면 렌더 실패). replicas 1 이라 후보 중 한 노드에만 뜬다.
  ⚠ hostNetwork 라 장비는 파드가 뜬 노드의 IP 로 보내야 한다 — 후보가 둘 이상이면 장비 쪽 대상이 둘 다 커버해야 한다.
    한쪽만 알면 다른 노드에 떴을 때 Running 인데 아무것도 받지 않는다.
- **`resources.requests` 는 당분간 주석 처리** — 304-airflow 와 같은 임시 조치. 여유가 생기면 푼다.

## 설치

전제: 300 · 301-kafka · 301-minio · 301-hadoop · 303-postgres 설치 완료, Harbor 에 이미지 6종
(`cdm-mapper` · `cdm-consumer-rdb/graph/warehouse` · `cdm-lineage-consumer` · `tcp-socket-collector`) push 완료.
301-hadoop 의 hook Job `hadoop-dirs` 가 `global.hadoop.warehouse.path`(`/warehouse`)를 `global.hadoop.warehouse.user` 소유로 만든다 —
없으면 warehouse 컨슈머가 첫 쓰기에서 권한 오류(`HADOOP_USER_NAME` 이 그 소유자와 같은 global 값이라 여기서 따로 맞출 것은 없다).

```bash
helm lint 307-pipeline -f values.common.yaml
helm template pipeline ./307-pipeline -f values.common.yaml
helm install pipeline ./307-pipeline -f values.common.yaml -n data-layer

kubectl -n data-layer get pod -l app=cdm-mapper -L cdm.mapper/module
kubectl -n data-layer get pod -l 'app in (cdm-consumer-rdb,cdm-consumer-graph,cdm-consumer-warehouse,cdm-lineage-consumer,tcp-socket-collector)' -o wide
```
