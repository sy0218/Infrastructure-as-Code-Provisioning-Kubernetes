# 301-neo4j

Neo4j 단일 인스턴스(Community) — 클러스터 내부 전용 그래프 DB. 307 의 cdm-consumer-graph 가 MERGE 로 적재하는 대상이다.

Deployment(Recreate) 1개 + RWO PVC(`longhorn`) + ClusterIP Service(7687 Bolt / 7474 HTTP)가 전부다 — 301-minio 와 같은 계열이다.
Community Edition 은 인스턴스 1개·DB 1개(`neo4j`)라 클러스터링이 없다. 그래서 **장애는 앱 복제가 아니라 Longhorn 스토리지 복제**로
막는다 — 노드가 죽으면 파드가 다른 노드에서 재기동되고 같은 볼륨을 붙는다(자동화 조건·검증·복구는 301-minio `RUNBOOK.md` 와 같다).
외부 노출은 없다 — 소비자가 전부 파드라 Service DNS 로 충분하고, Browser 는 사람이 port-forward 로 연다.

설정은 전부 env 다(`NEO4J_` 접두 env = 서버 설정, 그래서 공용 envFrom 을 쓰지 않는다). 계정은 공용 Secret 의 클라이언트 키
`PLATFORM_NEO4J_USER/PASSWORD` 를 `secretKeyRef` 로 받아 `NEO4J_AUTH` 로 조립한다 — 서버용 값을 따로 두지 않아 컨슈머와 갈릴 수 없다.
`NEO4J_AUTH` 는 사용자명 `neo4j` 만 받으므로 `global.secrets.neo4jUser` 가 다르면 렌더가 실패한다. 힙·페이지캐시는 values `memory`
로 고정한다 — 안 주면 노드 RAM(ap 64G) 기준으로 자동 산정해 과점한다.

이미지는 `data_pipeline/data_layer_graph/Dockerfile`(`neo4j:5.26.30-community`, 플러그인 없음 — 컨슈머는 MERGE/MATCH 만 쓴다) —
공용 `global.imageTag`.

## 설치

```bash
/project/data_pipeline/scripts/build_and_push.sh v0.1.0 neo4j   # Harbor 에 아직 없는 이미지 — 태그는 global.imageTag
helm lint 301-neo4j -f values.common.yaml
helm install neo4j ./301-neo4j -f values.common.yaml -n data-layer
```

선행: 100-base(longhorn) · 300-data-layer-base(공용 Secret `PLATFORM_NEO4J_*`). hook Job 이 없어 `--timeout` 은 기본값으로 충분하다.

## 전환 — `global.neo4jBoltUri`

`values.common.yaml` 의 `global.neo4jBoltUri` 는 이 차트의 Service FQDN(`bolt://neo4j.data-layer.svc.cluster.local:7687`)이다.
300 이 그 값을 `PLATFORM_NEO4J_URI` 로 만들고 307 graph 컨슈머가 `NEO4J_URI` 로 번역해 읽는다. 구 노드 로컬 주소(`bolt://192.168.56.38:7687`)는
실제 설치가 없었으므로 데이터 이관은 없다. 값을 바꾼 뒤에는 다른 릴리스라 해시가 없어 **사람이** 반영한다:

```bash
helm upgrade data-layer-base ./300-data-layer-base -f values.common.yaml -n default   # ConfigMap 재렌더
kubectl -n data-layer rollout restart deploy/cdm-consumer-graph                        # 새 URI 로 재기동
```

## 확인

```bash
kubectl -n data-layer get pod,pvc,svc -l app=neo4j -o wide
kubectl -n data-layer exec deploy/neo4j -- sh -c 'cypher-shell -u "$PLATFORM_NEO4J_USER" -p "$PLATFORM_NEO4J_PASSWORD" "RETURN 1"'   # 따옴표 안이라 컨테이너가 env 를 푼다
kubectl -n data-layer port-forward svc/neo4j 7474:7474 7687:7687   # → http://localhost:7474 (Browser, 접속 주소 bolt://localhost:7687)
```

## 주의

- `helm uninstall` 은 PVC 까지 지운다 — longhorn reclaimPolicy 가 Delete 라 **그래프 데이터가 함께 삭제된다**.
- 계정은 첫 기동(빈 `/data`)에만 `NEO4J_AUTH` 로 만들어진다 — 이후 `global.secrets.neo4jPassword` 를 바꿔도 DB 는 바뀌지 않는다
  (`ALTER USER neo4j SET PASSWORD` 를 먼저, 그 다음 값·300 upgrade·컨슈머 재기동).
- `ports.bolt` 를 바꾸면 `global.neo4jBoltUri` 의 포트도 같은 커밋에서 바꾼다.
- `memory.heap/pagecache` 를 올리면 deployment 의 memory request(2Gi)도 같이 올린다 — limits 는 두지 않는다.
