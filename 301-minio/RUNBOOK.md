# MinIO 운영 매뉴얼 — 노드 장애 페일오버

대상: Deployment `minio` / ns `data-layer` / 단일 인스턴스 + RWO PVC `minio-data`(longhorn)

이 차트의 가용성 주장은 하나뿐이다 — **노드가 죽으면 파드가 다른 노드에서 같은 볼륨을 붙어
서비스가 이어진다.** 그 주장이 성립하려면 아래 두 가지가 동시에 켜져 있어야 하고, 둘 중
하나라도 빠지면 조용히 실패한다(파드가 `Terminating` 에 영원히 걸린다).

| 조건 | 소유자 | 확인 |
|---|---|---|
| `nodeDownPodDeletionPolicy` = `delete-both-statefulset-and-deployment-pod` | `100-base/longhorn.tf` | `kubectl -n longhorn-system get setting node-down-pod-deletion-policy` |
| 파드 `tolerationSeconds`(기본 60) | 이 차트 values | `kubectl -n data-layer get deploy minio -o jsonpath='{..tolerations}'` |
| **옮겨 갈 노드에 `instance-manager` 파드가 있을 것** | 노드 CPU 여유 | `kubectl -n longhorn-system get pod -l longhorn.io/component=instance-manager -o wide` |

> ⚠ **세 번째 조건이 조용한 실패의 원인이다.** Longhorn 엔진·replica 프로세스는 그 노드의
> `instance-manager` 파드 **안에서** 돈다. 그 파드가 없는 노드로는 볼륨이 붙지 않고, 파드는
> `MountVolume.MountDevice failed ... hasn't been attached yet` 로 `ContainerCreating` 에 갇힌다.
> instance-manager 는 `guaranteed-instance-manager-cpu`(기본 12%) 만큼 CPU **request** 를
> 요구하는데, 이 랩의 노드는 2 vCPU 라 240m 이다. 노드 request 합이 1760m 을 넘으면 kubelet 이
> `OutOfcpu` 로 거부하고 **2분마다 조용히 재시도만 한다**(파드 목록에 아예 안 보인다).
> **테스트 전에 3노드 모두 instance-manager 가 떠 있는지 반드시 확인한다** — 없는 노드는
> 페일오버 목적지가 될 수 없고, 하필 거기로 스케줄되면 테스트가 실패한다.

> ⚠ 정책이 `do-nothing`(Longhorn 기본값)이면 **테스트는 반드시 실패한다.** kubelet 이 죽은 노드의
> 파드는 API 서버가 지울 수 없어 `Terminating` 으로 남고, RWO 볼륨이 안 풀려 새 파드도 못 뜬다.

## 1. 사전 조건

```bash
terraform -chdir=100-base apply     # 사용자가 직접 실행 (저장소 규칙)

# 반영 확인 — apply 만 믿지 말 것
kubectl -n longhorn-system get setting node-down-pod-deletion-policy \
  -o jsonpath='{.value}{"  CMRV="}{.metadata.annotations.longhorn\.io/configmap-resource-version}{"\n"}'
→ delete-both-statefulset-and-deployment-pod   / CMRV 이 새 ConfigMap resourceVersion 과 같아야 한다
```

값이 안 바뀌었으면 오타를 먼저 의심한다 — Longhorn 은 유효하지 않은 값을 **조용히 무시**한다.
```bash
kubectl -n longhorn-system logs -l app=longhorn-manager -c longhorn-manager \
  | grep -i 'Invalid customized default setting'
```

> Longhorn 1.11.3 은 `longhorn-default-setting` ConfigMap 을 watch 하는 전용 컨트롤러가 있어
> **helm upgrade 만으로 라이브 Setting 이 바뀐다**(재시작 불필요). "커스터마이즈한 기본 설정은
> 최초 기동 때만 적용된다"는 널리 알려진 경고는 **v1.3.0 미만 한정**이라 여기엔 해당하지 않는다.
>
> ⚠ 대신 반대 함정이 있다 — ConfigMap 에 실린 키는 UI/kubectl 로 바꿔도 다음 apply 때
> tf 값으로 되돌아간다(사용자 수정 여부를 보는 가드가 없다). **longhorn.tf 를 유일한 출처로 삼는다.**
> 반대로 ConfigMap 에 **없는** 키는 건드리지 않으므로, 원복은 tf 에서 줄을 지우는 것이 아니라
> `nodeDownPodDeletionPolicy = "do-nothing"` 을 명시해 apply 해야 한다.

## 2. 테스트 절차

### 2.1 카나리 심기
복구 후 "같은 데이터"를 증명할 대상을 먼저 넣는다. 콘솔이 꺼져 있어 관리 수단은 mc 뿐이다.
```bash
kubectl -n data-layer exec deploy/minio -- sh -c '
  mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" &&
  mc mb -p local/failover-test &&
  echo "canary-$(date +%s)" > /tmp/canary.txt &&
  dd if=/dev/urandom of=/tmp/blob.bin bs=1M count=20 2>/dev/null &&
  mc cp /tmp/canary.txt local/failover-test/ && mc cp /tmp/blob.bin local/failover-test/ &&
  mc cat local/failover-test/canary.txt && md5sum /tmp/blob.bin'
```

### 2.2 대상 파악 — **어느 노드를 죽일지가 이 테스트의 전부다**
```bash
kubectl -n data-layer get pod -l app=minio -o wide          # 파드가 뜬 노드
VOL=$(kubectl -n data-layer get pvc minio-data -o jsonpath='{.spec.volumeName}')
kubectl -n longhorn-system get replicas.longhorn.io --no-headers | grep $VOL   # replica 2개 위치
kubectl get pod -A -o wide --no-headers | awk -v n=<대상노드> '$8==n'          # 같이 죽는 것들
```

- **`ap` 는 절대 죽이지 않는다** — 단일 control-plane + etcd 이고, 작업 셸도 거기 있다.
  MinIO 가 ap 에 있으면 `kubectl -n data-layer delete pod -l app=minio` 로 먼저 옮긴다.
- replica 는 2개뿐이다. 죽일 노드가 replica 를 하나 갖고 있어도 남은 1개로 이어진다(degraded).
- **같이 죽는 것 중 스스로 못 돌아오는 게 있다** — `kafka-N`(hostNetwork + local PV)은 그 노드에
  고정이라 노드가 살아날 때까지 down 이다. RF 3 / `min.insync.replicas=1` 이라 Kafka 서비스
  자체는 이어지지만 URP 가 생긴다. CNPG 인스턴스가 **primary** 면 Postgres failover 도 함께 일어난다.

### 2.3 죽이기
```bash
ssh root@<대상노드> poweroff                        # A. 전원 차단 (가장 충실)
ssh root@<대상노드> 'echo b > /proc/sysrq-trigger'  # B. 즉시 리셋 (sync 없음 — 진짜 크래시에 가깝다)
```
`shutdownGracePeriod: 0s` 라 kubelet 이 graceful node shutdown 을 하지 않는다 — 둘 다 제어 평면
입장에서는 "심장박동이 멎었다"로 동일하게 보인다.

> ⚠ **`systemctl stop kubelet` 은 쓰지 않는다.** 컨테이너가 계속 살아 있어 노드만 NotReady 가
> 되고 MinIO 프로세스는 볼륨을 잡은 채로 남는다. 강제 삭제 후 다른 노드가 같은 볼륨에 붙으면
> 이중 마운트가 된다(이 클러스터는 `disableRevisionCounter=true` 라 방어막도 한 겹 없다).

> **A(전원 차단)를 쓰면 게스트 안에서는 되살릴 수 없다.** 호스트에서 `vagrant up <노드>` 를 해야
> 한다. 게스트 안에서만 완결하고 싶으면 B 를 쓰되 `systemctl disable kubelet` 을 먼저 걸어
> 재부팅 후에도 NotReady 로 남게 한다(복구는 `systemctl enable --now kubelet`).

### 2.4 관찰
```bash
kubectl -n data-layer get pod -l app=minio -o wide -w
kubectl get nodes -w
watch -n2 "kubectl -n longhorn-system get volumes.longhorn.io $VOL \
  -o custom-columns=STATE:.status.state,ROBUST:.status.robustness,NODE:.status.currentNodeID"
kubectl -n longhorn-system logs -l app=longhorn-manager -c longhorn-manager -f | grep -i 'downed node'
```

## 3. 판정 — 이 순서대로 일어나야 정상

| 시점(누적) | 무슨 일 | 보이는 것 |
|---|---|---|
| ~50s | `node-monitor-grace-period` 만료 | 노드 `NotReady`, `unreachable:NoExecute` taint |
| ~110s | taint-manager 가 `tolerationSeconds`(60) 만료 후 파드 삭제 | 파드 `Terminating` (여기서 **멈춘다** — kubelet 이 없다) |
| +α | Longhorn 이 강제 삭제 → 볼륨 detach | 파드 사라짐, 볼륨 `detached` |
| ~2~3분 | 새 노드에 스케줄 + reattach | 새 파드 `Running`, 볼륨 `attached` / 새 `currentNodeID` |
| +10분 | `replica-replenishment-wait-interval`(600s) 만료 | 남은 노드에 replica 재구축 → `robustness: healthy` |

> **60초 안에 안 옮겨간다고 실패로 판정하지 말 것.** Longhorn 이 파드를 강제 삭제하려면 그 파드에
> **먼저 `DeletionTimestamp` 가 찍혀 있어야 한다** — 설정만으로 Longhorn 이 스스로 지우지는 않는다.
> 즉 toleration 만료(60s)가 지나야 비로소 Longhorn 차례가 온다.

볼륨이 `degraded`(replica 1/2)로 10분간 머무는 것은 **정상**이다. 서비스에는 영향이 없다.

## 4. 복구

```bash
vagrant up <노드>                              # 호스트에서 (전원 차단이었을 때)
ssh root@<노드> 'systemctl enable --now kubelet'  # 게스트에서 (kubelet 비활성 재부팅이었을 때)

kubectl get nodes
kubectl -n longhorn-system get volumes.longhorn.io $VOL   # → attached / healthy
kubectl -n data-layer get pod -l app=kafka -o wide        # kafka-N 재기동
kubectl -n data-layer exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --describe --under-replicated-partitions
→ 빈 출력이 될 때까지 기다린다 (URP 0)
```

무결성 확인 — 2.1 에서 넣은 값과 글자 그대로 같아야 한다.
```bash
kubectl -n data-layer exec deploy/minio -- sh -c '
  mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" &&
  mc cat local/failover-test/canary.txt &&
  mc cp local/failover-test/blob.bin /tmp/b.bin && md5sum /tmp/b.bin'
```

정리:
```bash
kubectl -n data-layer exec deploy/minio -- sh -c '
  mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" &&
  mc rb --force local/failover-test'
```

## 5. 자주 쓰는 명령어

콘솔이 없다(`MINIO_BROWSER=off`). 버킷·계정·정책 작업은 전부 mc 로 한다.
```bash
alias mcx='kubectl -n data-layer exec deploy/minio -- sh -c '"'"'mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; mc '"'"

kubectl -n data-layer exec deploy/minio -- sh -c 'mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null; mc ls local/'
kubectl -n data-layer exec deploy/minio -- sh -c '... ; mc admin info local'
kubectl -n data-layer exec deploy/minio -- sh -c '... ; mc du local/<버킷>'
```

클러스터 내부 접속 주소(파이프라인 전환 시 이 값):
```
http://minio.data-layer.svc.cluster.local:9000
```

## 6. 이 문서가 다루지 않는 것

- **디스크가 아니라 노드가 죽는 경우만** 다룬다. Longhorn 디스크 자체의 장애·replica 재구축
  실패는 Longhorn UI 와 `kubectl -n longhorn-system get volumes.longhorn.io` 로 따로 본다.
- **버킷 부트스트랩**은 별개다 — `config`·`warehouse` 버킷과 설정 시드는 README '버킷' 의 mc 절차로 만든다.
- **백업이 아니다.** Longhorn replica 2 는 노드 1대 장애를 견디는 것이지, 실수로 지운 객체를
  되살리지 못한다. 버킷 백업이 필요해지면 별도 수단을 둔다.
