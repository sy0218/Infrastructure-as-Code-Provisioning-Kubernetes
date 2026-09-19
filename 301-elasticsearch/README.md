# 301-elasticsearch

Elasticsearch 3노드 클러스터 — 클러스터 내부 전용 검색 엔진.

**장애는 쿠버네티스가 아니라 ES 자체 복제로 막는다** — 301-kafka·301-hadoop 과 같은 원칙이다.
hostNetwork(파드 IP = 노드 IP = publish 주소) + 정적 local PV(`elasticsearch-local`, Retain)로 파드 ↔ 노드 ↔ 디스크를 고정하고,
마스터 과반(3 중 2) + 인덱스 replica(기본 1)로 노드 1대 장애를 넘긴다. Longhorn 을 쓰지 않는 이유 — 복제를 ES 가 이미 하므로
스토리지 복제는 이중이고, 로컬 디스크가 더 빠르다.

| 오브젝트 | 이름 | 역할 |
|---|---|---|
| StatefulSet | `elasticsearch` (파드 `elasticsearch-0..2`) | master+data 3 — **hostNetwork**(9200/9300), `updateStrategy: OnDelete` |
| StorageClass | `elasticsearch-local` | 프로비저너 없음, `WaitForFirstConsumer`, `Retain` — 정적 local PV 전용 |
| PersistentVolume ×N | `elasticsearch-<노드>` | `/data/elasticsearch` 20Gi — **`claimRef` 로 PVC `data-elasticsearch-N` 에 미리 묶여** ordinal ↔ `nodeNames[N]` 고정 |
| Service | `elasticsearch` | ClusterIP 9200 — 파드 안 소비자의 고정 진입점(엔드포인트 = 준비된 노드 IP). transport 는 노드 IP 직결이라 없다 |

설정 파일이 없다 — 점(.) 이름 env 가 곧 ES 설정이다. `discovery.seed_hosts` 는 values `nodeNames` → `global.nodes` IP 파생(`_helpers.tpl`,
표에 없는 이름은 렌더 실패), `node.name` = 파드 이름, `network.publish_host` = 노드 IP. 보안(xpack.security)은 꺼서 HTTP 평문이다 —
켜면 TLS·비밀번호 부트스트랩이 따라와 소비자 전부가 인증서를 들어야 한다.

이미지는 `data_pipeline/data_layer_elasticsearch/Dockerfile`(`elasticsearch:9.5.3` 재호스팅, `FROM` 한 줄) — 공용 `global.imageTag`.

## 설치

```bash
bin/start_elasticsearch_prereq.sh <Ansible 절대경로> all                # 노드 /data/elasticsearch (root:root 2770) — Ansible 저장소에서
/project/data_pipeline/scripts/build_and_push.sh v0.1.0 elasticsearch   # Harbor 에 아직 없는 이미지 — 태그는 global.imageTag
helm lint 301-elasticsearch -f values.common.yaml
helm install elasticsearch ./301-elasticsearch -f values.common.yaml -n data-layer
```

선행: 300-data-layer-base(네임스페이스). hook Job 이 없어 `--timeout` 은 기본값으로 충분하다.
9200/9300 은 노드 전체에서 유일해야 한다(`ss -lnt`). `vm.max_map_count` 는 262144 이상(Ubuntu 24.04 기본 1048576 —
미달이면 부트스트랩 검사로 기동 거부).

## 확인

```bash
kubectl -n data-layer get pod,pv,pvc -l app.kubernetes.io/name=elasticsearch -o wide
curl -s '192.168.56.38:9200/_cluster/health?pretty'   # status green, number_of_nodes 3
curl -s '192.168.56.38:9200/_cat/nodes?v'             # 셋 다 보이고 master(*) 는 하나
```

## 노드 장애 · 롤링 재기동

- 노드가 죽으면 그 파드는 옮겨 가지 않는다(PV 가 노드에 못박혀 Pending). 남은 2대가 마스터 과반을 유지하고 replica 가 primary 로
  승격해 서비스를 잇는다 — 상태는 yellow. 노드가 돌아오면 파드가 같은 디스크로 다시 붙고 green 이 된다.
- 2대가 동시에 죽으면 과반이 깨져 마스터 선출·쓰기가 멈춘다 — 3노드 설계의 한계.
- **`updateStrategy: OnDelete`** — 설정·이미지 변경 뒤 `kubectl -n data-layer delete pod elasticsearch-2` 부터 한 대씩,
  매번 `_cluster/health` 가 green 으로 돌아온 뒤 다음으로.
- 인덱스 `number_of_replicas` 는 기본 1 을 유지한다 — 0 이면 노드 1대 장애가 곧 데이터 유실이다.

## 주의

- `helm uninstall` 은 PVC(volumeClaimTemplates)를 남긴다 — **재설치 전에 PVC 를 먼저 지운다**
  (`kubectl -n data-layer delete pvc -l app.kubernetes.io/name=elasticsearch` — PV 는 Retain 이라 디스크 데이터는 그대로).
  PV 가 `Released` 로 남으면 `claimRef.uid` 만 patch 로 비운다(301-kafka README 'PV 재사용').
- `nodeNames` 증설은 표 뒤에 붙이고 축소는 뒤에서 뺀다 — 그 노드에 디렉토리(Ansible)가 먼저 있어야 한다.
  `data.path` 는 Ansible `group_vars/elasticsearch.yml` 의 `elasticsearch_data_dir` 와 같은 커밋 규칙.
- `podManagementPolicy`·`serviceName` 은 불변 → `kubectl delete sts elasticsearch --cascade=orphan` 후 upgrade.
- `resources.requests`(250m / 1536Mi × 3)는 유지한다. 힙(values `heap`)을 올리면 같이 올린다 — limits 는 두지 않는다.
