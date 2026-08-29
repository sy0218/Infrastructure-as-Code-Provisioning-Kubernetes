# 301-kafka — Helm 차트

**Kafka 클러스터(StatefulSet) + 운영 도구 3종.** 구 `301-kafka-tools` 를 개명·통합했고, 브로커는 구 Ansible
systemd 설치(ADR 0)를 K8s 로 그대로 옮긴 것이다 — **오퍼레이터를 쓰지 않는다.** 브로커는 노드에 박힌 인프라이고
쿠버네티스는 실행기다. 네임스페이스·공용 ConfigMap/Secret 은 300-data-layer-base 가, 노드 디렉토리는 Ansible
`kafka_prereq` 가 소유하고, 이 차트는 **StatefulSet·정적 PV·설정·토픽 Job·도구 3종**을 소유한다.
추후 ArgoCD app-of-apps 에서는 sync-wave 1 (300 다음)이다.

| 오브젝트 | 이름 | 역할 |
|---|---|---|
| StatefulSet | `kafka` (파드 `kafka-0..2`) | KRaft 브로커 3 — 앞 `controllers`(3)개는 controller+broker 겸용. **hostNetwork**, `updateStrategy: OnDelete` |
| Service | `kafka` / `kafka-hl` | 클러스터 안 bootstrap(ClusterIP, readiness 통과분만) / STS headless(파드 DNS) |
| StorageClass | `kafka-local` | 프로비저너 없음, `WaitForFirstConsumer`, `Retain` — 정적 local PV 전용 |
| PersistentVolume ×6 | `kafka-{data,metadata}-<노드>` | `/data/kafka-broker`(10Gi, log.dirs) · `/data/kafka-controller`(2Gi, metadata.log.dir). **`claimRef` 로 PVC `data-kafka-N` 에 미리 묶여** kafka-N ↔ nodes[N] 고정 |
| ConfigMap | `kafka-config` | `server.properties.tpl` — 구 Ansible server.properties 승계. 파드별 값은 기동 스크립트가 채움 |
| ConfigMap | `kafka-jmx-exporter` | JMX exporter 룰(`files/jmx-exporter.yaml`) → 파드 :9404 `metrics` |
| Job (helm hook) | `kafka-topics` | 파이프라인 계약 토픽 16개 `--if-not-exists` (파티션 3 / RF 3) — 구 `kafka_topics` 롤 승계 |
| Deployment + Service | `schema-registry` | Avro 스키마 저장·검증 (포트 9096) |
| Deployment + Service | `kafka-ui` | 토픽·컨슈머 그룹 웹 콘솔 (포트 9095) |
| Deployment + Service | `kafka-exporter` | 토픽·오프셋·Lag → Prometheus (포트 9097) — 302-monitoring 이 긁어간다 |
| Ingress | `kafka-ui` | `http://data-layer-kafka-ui` (Host 기반, 포트 없음) |

## 설계 원칙 — 장애는 쿠버네티스가 아니라 Kafka 복제로 막는다

```
Node ap          Node s1          Node s2
kafka-0          kafka-1          kafka-2        ← 브로커 ID = 파드 ordinal = kafka.nodes 표 인덱스
192.168.0.38     192.168.0.39     192.168.0.40   ← hostNetwork: 파드 IP = 노드 IP = 광고 주소
/data/kafka-*    /data/kafka-*    /data/kafka-*  ← 정적 local PV, 노드에 못박힘
   └──────── Kafka Replication (RF 3) ────────┘
```

- **hostNetwork.** 파드 IP 가 노드 IP 이고 `advertised.listeners` 도 노드 IP:9092 다. 클러스터 안팎이 같은 주소로
  붙고 Service·NodePort·VIP 어느 것도 경로에 없다(bootstrap Service 는 첫 접속 한 번뿐). 대가: 9092/9093/9094/9404 는
  노드 전체에서 유일해야 하고, 브로커 ID ↔ 노드 IP 가 고정된다(`controller.quorum.voters`).
- **브로커 ↔ 노드 고정은 PV 의 `claimRef` 가 한다.** StatefulSet 이 만들 PVC 이름(`data-kafka-N`)에 PV 를 미리 묶어
  두면 kafka-N 은 nodes[N] 에만 스케줄된다. local-path 를 쓰지 않는 이유 — 파드가 다른 노드에 뜨면 빈 디스크에서
  시작한다.
- **노드가 죽으면 그 파드는 다른 노드로 못 옮긴다.** 죽은 직후에는 kubelet 이 종료를 확인 못 해 파드가 그 노드에
  Terminating/Unknown 으로 남고, Node 를 지운 뒤 재생성된 파드는 PV 가 없어 Pending 에 멈춘다. 이것이 의도다 —
  쿠버네티스가 빈 디스크로 브로커를 "복구"하면 `advertised.listeners`(노드 IP)와 데이터가 어긋난 브로커가 생긴다.
  남은 브로커 2대가 RF 3 복제본으로 서비스를 잇고(`min.insync.replicas=1` — 구 로컬 설치 계약의 승계, 가용성 우선),
  KRaft 쿼럼은 3 중 2 로 유지된다.
- **`updateStrategy: OnDelete`.** 설정·이미지가 바뀌어도 파드가 저절로 재기동되지 않는다. RollingUpdate 는 '포트가
  열림' 만 보고 다음 브로커를 내리는데, 복제가 따라잡히기 전에 두 번째를 내리면 파티션이 오프라인이 된다. 사람이
  한 대씩 지우며 URP 0 을 확인한다('롤링 재기동').
- **Strimzi 를 쓰지 않는다.** `hostNetwork`/`hostPort` 를 지원하지 않아(PodTemplate 에 필드 없음, upstream #3753·#7397
  기각) 외부 접속이 NodePort(30xxx + DNAT)로 갈라진다. 운영 편의(안전 롤링·토픽 CR·업그레이드 조율)를 잃는 대신
  노드 직결과 단순성을 택했다 — 그 운영 작업은 아래 절차로 사람이 한다.

## values 계약

- `global.*` — 네임스페이스 + 배포 공통값(harborRegistry·imageTag·ingressClassName). 브로커 이미지(`kafka`)와 도구 3종
  이미지가 같은 태그를 쓴다.
- `kafka.*` — `name`(파드/Service 접두) · `clusterId`(KRaft, 디스크에 각인) · `imageName` · `ports` · **`nodes` 표** ·
  `controllers` · `storageClass` · `data/metadata.{path,size}` · `heap` · `resources` · 복제 기본값 · `terminationGracePeriodSeconds`.
- `topics` — 토픽 Job 목록. 빼도 토픽은 지워지지 않는다(삭제는 수동).
- 나머지 최상위 키 — 도구 3종(포트 3종·복제 수·`kafkaUiHost`).
- `values.schema.json` 이 필수 키·형식(노드 3 이상·중복 금지, IP 형식, `controllers` 3|5, 경로 절대경로, requests-only,
  토픽 이름 등)을 렌더 시점에 강제한다.

### 복사본/커플링 값 (바꿀 때 같은 커밋에서 함께)

- `kafka.name` + `ports.client` → 브로커 주소 `kafka.data-layer.svc.cluster.local:9092`. **이 차트가 원본**이고 300 의
  `global.kafkaBootstrap`(→ 공용 ConfigMap `KAFKA_BOOTSTRAP`), `data_pipeline/data_layer_kafka/kafka.conf` 의
  `BOOTSTRAP`/`POD` 가 복사본. 차트 안에서는 `_helpers.tpl` 의 `kafka.bootstrap` 이 유일한 조립 지점.
- `kafka.nodes[].ip` → Ansible `host.yml` 의 노드 IP. `controller.quorum.voters` 와 광고 주소가 여기서 나온다.
- `kafka.data.path` / `kafka.metadata.path` → Ansible `group_vars/kafka.yml` 의 `kafka_broker_data_dir` /
  `kafka_controller_data_dir` 와 글자 그대로 같아야 한다.
- `kafka.ports.*` → 노드에서 유일해야 한다(hostNetwork). 302-monitoring 은 포트 번호가 아니라 이름 `metrics` 로 긁는다.
- `schemaRegistryPort` · `kafkaUiHost` → 300 이 URL 문자열(`SCHEMA_REGISTRY_URL`·`KAFKA_UI_URL`) 조립용 복사본을 갖는다.

### 규칙 예외 (문서화된 의도)

1. **hostNetwork + `dnsPolicy: ClusterFirstWithHostNet`** — tcp-socket-collector·alloy 와 같은 예외. 파드 안 CLI 가
   svc 이름을 부를 수 있게 한다(브로커 자신은 IP 만 쓴다).
2. **`resources` 에 limits 가 없는 대신 힙을 고정한다**(`KAFKA_HEAP_OPTS -Xms=-Xmx`). limit 이 없으면 JVM 이 노드
   MemTotal 의 25% 를 향해 자란다.
3. **`securityContext.fsGroup: 0` + `OnRootMismatch`.** 컨테이너는 apache/kafka 의 appuser 이고 디렉토리는 root:root
   **2770** 이라 gid 0 그룹 쓰기로 붙는다. `OnRootMismatch` 는 최상위의 gid·rwx·setgid 가 전부 맞아야 건너뛴다 —
   kubelet 이 첫 기동 때 재귀 chown 을 하며 setgid 를 켜 2770 이 되므로 Ansible `kafka_data_mode` 도 `'2770'` 이어야
   한다(`'0770'` 이면 재실행마다 setgid 가 벗겨져 다음 재기동 때 데이터 전체를 다시 chown 한다).
4. **이미지의 엔트리포인트(`/etc/kafka/docker/run`)를 쓰지 않는다.** 그 경로의 env→properties 변환은 설정을 env 수십
   개로 흩고, `kafka-storage format` 을 `--ignore-formatted` 없이 돌린다. 차트는 `server.properties` 한 장을 ConfigMap 으로
   소유하고 기동 스크립트가 `format --ignore-formatted` → `kafka-server-start.sh` 를 직접 돈다(302 의 prometheus.yml 과 같은
   '설정은 이미지가 아니라 ConfigMap 이 소유' 원칙).

## 설치

전제(순서대로):
1. **Ansible `kafka_prereq`** — `kafka.nodes` 의 노드마다 `/data/kafka-broker`·`/data/kafka-controller`
   (root:root **2770** — `group_vars/kafka.yml` 의 `kafka_data_mode`). 없으면 그 노드의 파드가 마운트 실패로 멈춘다.
2. **노드 포트** 9092/9093/9094/9404 가 비어 있을 것 — `ss -lnt | grep -E ':(909[2-4]|9404)$'` 가 빈 출력.
3. **Harbor 이미지** — `data_pipeline/scripts/build_and_push.sh v0.1.0 kafka kafka-ui kafka-exporter schema-registry`.
4. **300-data-layer-base install** — 네임스페이스·공용 ConfigMap/Secret. 300 의 `global.kafkaBootstrap` 이 이 차트의
   bootstrap 주소를 가리켜야 도구 3종·파이프라인이 붙는다.
5. **노드 실사용 메모리** — 브로커(힙 1g + 네이티브 ≈ 1.5GB RSS)는 PV 때문에 반드시 그 노드에 뜬다. control-plane ap 는
   requests 없는 프로세스(apiserver·etcd·cilium·longhorn)가 실사용을 채우고 있으니 `free -m` 으로 노드마다
   MemAvailable ≥ 2GB 를 확인한다. 부족하면 `kafka.heap` 을 768m 로 낮춘다.

release 를 `data-layer` 에 두는 이유: 300 과 달리 네임스페이스가 이미 있고, 이 차트의 네임스페이스 오브젝트 전부가
그 안에 있다(StorageClass·PV 는 클러스터 범위지만 기록 위치와 무관).

```bash
helm lint 301-kafka                                        # 문법 + 스키마 검사
helm template kafka ./301-kafka                            # 미리보기 (클러스터 접근 없음)
helm install kafka ./301-kafka -n data-layer               # 토픽 Job(hook)이 끝나야 돌아온다 — 브로커 3대 기동 포함 수 분

# 확인
kubectl -n data-layer get pod -l app=kafka -o wide         # kafka-0@ap / kafka-1@s1 / kafka-2@s2, IP = 노드 IP
kubectl -n data-layer get pvc | grep kafka                 # data-kafka-N / metadata-kafka-N Bound ×6
kubectl get pv -l app.kubernetes.io/name=kafka             # Bound ×6
kubectl -n data-layer exec kafka-0 -- /opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server localhost:9092 describe --status   # 쿼럼 3, 리더 1
kubectl -n data-layer exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list                       # 16개
kubectl -n data-layer rollout status deploy/schema-registry deploy/kafka-ui deploy/kafka-exporter
ss -lnt | grep -E ':(909[2-4]|9404)$'                      # 노드에서 — 브로커가 점유 중
```

## 외부 접속

hostNetwork 라 클러스터 밖에서는 **노드 IP:9092** 로 직접 붙는다 — Service 도 NodePort 도 없다. bootstrap 은 노드 IP 3개를
전부 적는다(한 대 죽어도 붙는다). 클라이언트는 bootstrap 뒤 브로커가 광고한 노드 IP 로 직접 간다.

```bash
kafka-console-consumer.sh --bootstrap-server 192.168.0.38:9092,192.168.0.39:9092,192.168.0.40:9092 --topic cdm-topic --from-beginning
```

클러스터 안 워크로드는 공용 ConfigMap 의 `KAFKA_BOOTSTRAP`(`kafka.data-layer.svc.cluster.local:9092`)을 쓴다 —
Service 는 readiness 통과한 브로커만 엔드포인트로 두므로 죽은 브로커로 첫 접속을 보내지 않는다.

## 일상 운영

```bash
helm lint 301-kafka
helm template kafka 301-kafka | kubectl diff -f -               # 라이브와 대조
helm upgrade kafka ./301-kafka -n data-layer                    # 값 반영 — 브로커 파드는 OnDelete 라 아래 '롤링 재기동' 필요
kubectl -n data-layer logs kafka-0 --tail=100                   # 기동 로그 (== kafka-0 roles=… advertised=… == 로 시작)
```

- **`helm uninstall`** 은 StatefulSet·Service·PV 오브젝트를 지운다. PVC(volumeClaimTemplates)와 디스크 데이터는 남는다 —
  재설치 시 PV 가 다시 생기고 같은 PVC 이름에 `claimRef` 로 묶이므로 데이터가 이어진다(같은 `clusterId` 전제).
  데이터를 버리려면 PVC 삭제 + 노드 디렉토리 비우기.
- **파티션 수 변경 금지**(`numPartitions`) — 프로듀서가 `hash(key) % 파티션` 으로 파티션을 고르므로 순서 보장이 깨진다.
- **`clusterId` 변경 금지** — 디스크의 `meta.properties` 와 충돌해 브로커가 뜨지 않는다(= 데이터 초기화가 전제).
- Kafka 버전 업: `data_layer_kafka/Dockerfile` 의 FROM → push → `global.imageTag` → 롤링 재기동. KRaft
  `metadata.version` 은 `kafka-features.sh upgrade --metadata <ver>` 로 별도(브로커 전부 새 버전이 된 뒤).
- CLI: `kubectl -n data-layer exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list`
  (`data_pipeline/data_layer_kafka/*.sh` 래퍼의 `POD`/`BOOTSTRAP` 도 이 이름을 가리킨다). 브로커의 힙·javaagent 는
  파드 env 가 아니라 기동 스크립트 안에서만 `export` 되므로 exec 로 띄운 CLI JVM 은 그것을 물려받지 않는다
  (물려받으면 javaagent 가 9404 를 또 열다 JVM 이 죽는다 — 파드 env 로 되돌리지 말 것).

## 롤링 재기동 (설정·이미지 변경 반영)

`updateStrategy: OnDelete` 라 `helm upgrade` 는 StatefulSet 템플릿만 바꾸고 파드는 그대로 둔다. 한 대씩:

```bash
for i in 2 1 0; do                                                           # 리더가 몰린 쪽을 나중에 — 보통 역순
  kubectl -n data-layer delete pod kafka-$i                                  # controlled shutdown(리더 이전) 후 새 템플릿으로 재기동
  kubectl -n data-layer wait --for=condition=Ready pod/kafka-$i --timeout=300s
  until [ -z "$(kubectl -n data-layer exec kafka-$i -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
                 --describe --under-replicated-partitions 2>/dev/null)" ]; do sleep 5; done   # URP 0 이 될 때까지
done
```

`kubectl get pod kafka-N -o jsonpath='{.metadata.annotations.checksum/config}'` 와 STS 템플릿의 값이 다르면 아직 반영
안 된 파드다.

## PV 재사용 (Released → Available)

`Retain` PV 는 PVC 가 지워지면 `spec.claimRef` 에 옛 PVC 의 uid 가 남아 **Released** 가 되고, 같은 이름의 새 PVC 에도
바인딩되지 않는다. 생기는 경우: PVC 수동 삭제 뒤 재생성, 노드 교체 뒤 옛 PV 가 남았을 때.

```bash
kubectl get pv -l app.kubernetes.io/name=kafka                               # STATUS Released 확인
# 데이터를 이어받을 때: uid 만 비운다 → 이름이 같은 PVC 에 다시 바인딩
kubectl patch pv kafka-data-s1 --type=json -p '[{"op":"remove","path":"/spec/claimRef/uid"},{"op":"remove","path":"/spec/claimRef/resourceVersion"}]'
# 데이터를 버릴 때: 그 노드의 디렉토리를 비운 뒤 같은 patch
```

PV 오브젝트는 helm 릴리스 소유라 `helm upgrade` 가 표(`kafka.nodes`)에 따라 만들고 지운다.

## 노드 장애

전제: 오퍼레이터가 없으니 "선언 ↔ 실체" 도 사람이 맞춘다. 사람이 하는 일은 **표(`kafka.nodes`) 수정 + 죽은 노드의
파드/PVC 정리 + 롤링 재기동 + 복제 확인**이다. 노드 IP 가 광고 주소이자 쿼럼 voter 라, 노드가 바뀌면 전 브로커의
`controller.quorum.voters` 가 바뀐다 — 그래서 롤링이 들어간다(2번 이유 — 네트워크 identity).

```
노드 s1 사망 — kafka-1 은 s1 에 바인딩된 채 남는다 (Running/Unknown → 약 5분 뒤 Terminating; Node 를 지우기 전엔 안 사라진다)
 ↓ 서비스는 유지된다: RF 3 / ISR 1, 쿼럼 3 중 2. 클라이언트는 브로커 목록으로 살아 있는 쪽에 붙는다
 ↓
[A] 노드를 살릴 수 있으면 — 노드 복구 → kubelet 이 돌아와 kafka-1 이 같은 디스크·같은 IP 로 재기동 → 복제 따라잡음 → 끝.
      확인: URP 0 (아래 4번 명령)
[B] 노드가 영구 소실이면 — 같은 ID(kafka-1)를 새 노드 s3 에서 빈 디스크로 다시 띄운다. Kafka 가 다시 복제한다.
 ↓
0. 노드 제거      kubectl delete node s1        ← 영구 소실 확정 후. PodGC 가 kafka-1 파드를 지우고 STS 가 같은 이름으로 다시 만든다(PV 없음 → Pending)
 ↓
1. 새 노드 준비   Ansible: k8s join → kafka_prereq (디렉토리 2종, 2770)              ← 디렉토리가 먼저다
 ↓
2. 표 교체        values kafka.nodes[1]: {name: s1, ip: 192.168.0.39} → {name: s3, ip: 192.168.0.41} → helm upgrade
                  → PV kafka-{data,metadata}-s1 삭제, kafka-{data,metadata}-s3 생성(claimRef data-kafka-1) — 아직 옛 PVC 가 붙어 있어 Pending
                  → ConfigMap 의 controller.quorum.voters 가 1@192.168.0.41 로 바뀜 (파드는 OnDelete 라 그대로)
 ↓
3. 옛 PVC 정리    kubectl -n data-layer delete pvc data-kafka-1 metadata-kafka-1   (PV 가 사라져 Lost 상태 — 데이터는 죽은 노드에 있었음)
                  kubectl -n data-layer delete pod kafka-1                          → STS 가 PVC 를 다시 만들고 s3 PV 에 바인딩 → kafka-1 이 s3 에서 빈 디스크로 기동
                  (같은 node.id·같은 clusterId 라 리더들이 kafka-1 의 파티션을 다시 복제해 ISR 에 넣고, 컨트롤러는 쿼럼 리더에게서 메타데이터를 받는다)
 ↓
4. 복제 확인      kafka-topics.sh --describe --under-replicated-partitions → 빈 출력
                  kafka-metadata-quorum.sh describe --replication → 1 의 lag 0
 ↓
5. 롤링 재기동    kafka-0, kafka-2 를 '롤링 재기동' 절차로 한 대씩 — voters 의 1@IP 가 바뀌었으므로 반영해야 다음 리더 선출 때 s3 를 안다
                  (그 전까지는 옛 IP 로 1 을 찾지 못하지만 2 대 쿼럼이라 동작에는 지장 없다 — 미루지 말 것: 하나 더 죽으면 쿼럼 상실)
 ↓
6. 전체 확인      파드 3 Running (s3 에 kafka-1) / PVC 6 Bound / PV 6 Bound / URP 0 / kafka-ui 에서 브로커 0,1,2
```

- **한 번에 하나만 교체한다.** 빈 디스크로 뜬 컨트롤러는 리더에게서 메타데이터 로그를 받아 오지만, 3 중 2 가 동시에 빈
  디스크면 빈 로그끼리 리더를 뽑아 메타데이터를 잃을 수 있다(정적 쿼럼의 알려진 함정). 4번의 lag 0 을 본 뒤에 다음 노드를 손댄다.
- 새 노드가 IP 까지 그대로 물려받으면(예: 같은 IP 로 재설치) 2·5번의 voters 변경이 없어 롤링이 필요 없다 — 랩에서는 이쪽이 더 간단하다.

### 브로커 증설 / 축소 (노드 수가 바뀔 때)

컨트롤러 겸용은 앞 3개(`controllers`)로 고정이고, 4번째부터는 broker 전용으로 붙는다. 파티션 재배치는 사람이 한다.

```
증설: kafka_prereq(s3) → values kafka.nodes 뒤에 {name: s3, ip: …} 추가 → helm upgrade → kafka-3 기동 (빈 브로커, roles=broker)
      → 기존 파티션을 옮기려면 kafka-reassign-partitions.sh (--generate → --execute → --verify) — 안 옮기면 새 토픽/파티션만 s3 로 간다
축소: 뺄 브로커(가장 큰 ordinal)의 파티션을 먼저 다른 브로커로 재배치(--verify 로 완료 확인)
      → values kafka.nodes 에서 마지막 항목 삭제 → helm upgrade → STS 가 kafka-3 종료, PV 삭제 → PVC data-kafka-3 수동 삭제
```

StatefulSet 은 ordinal 뒤에서부터만 줄어든다 — 중간 브로커를 빼는 것은 '노드 장애 [B]' 의 교체 절차다. `controllers`
자체(3)는 정적 쿼럼이라 바꾸지 않는다.

## 추후 ArgoCD

이 차트는 그대로 ArgoCD Application 의 `source.path` 가 될 수 있다. `global.*` 는 app-of-apps 루트 values 가 주입한다.
`OnDelete` 는 Argo 의 sync 뒤에도 파드가 그대로인 것이 정상이므로 health 를 StatefulSet 의 `updatedReplicas` 로 보지
않도록 한다(토픽 Job 은 hook 으로 Argo 의 PostSync 에 대응).
