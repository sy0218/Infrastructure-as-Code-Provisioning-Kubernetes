# 304-airflow-rsync — Helm 차트

**304-airflow 가 hostPath 로 읽는 DAG/코드 디렉토리를 노드 간에 맞추는 Sync Pod.** 원본 노드(`source.nodeName`, ap)의
`repoPath` 를 읽기 전용 hostPath 로 마운트해 **inotify 로 감시하고, 변경이 오면 대상 노드(`targets.nodeNames`) 전부에 rsync** 한다.
이벤트가 없어도 `sync.intervalSeconds` 마다 전체를 다시 맞춘다(놓친 이벤트·꺼져 있던 노드의 복귀를 따라잡는 안전망).

Ansible `airflow_repo_prereq` 의 `sync` 태그(사람이 실행)를 상시 파드로 옮긴 것이다 — rsync 옵션·제외 목록이 같고,
달라진 것은 "DAG 을 고친 뒤 사람이 rsync 를 치는" 단계가 없어졌다는 점뿐이다. 노드 디렉토리 **생성**(`all` 태그)은 여전히 Ansible 선행작업이다.

```text
DAG 수정 (ap:/project/data_pipeline/data_layer_airflow)
   ↓ inotify (debounceSeconds 묶음) / intervalSeconds 주기
airflow-rsync Pod ── rsync over ssh ──▶ s1 · s2 (같은 경로)
   ↓
304-airflow dag-processor 재스캔(dagRefreshInterval) → 워커는 자기 노드의 로컬 디렉토리를 읽는다
```

| 오브젝트 | 이름 | 역할 |
|---|---|---|
| Deployment | `airflow-rsync` | replicas 1 · `Recreate` · `source.nodeName` 에 nodeAffinity 고정. root 로 돈다(0600 개인키 읽기 + 대상에 root 로 붙어 `--archive` 소유권 유지) |
| ConfigMap | `airflow-rsync-script` | `sync.sh` — 파드 템플릿의 `checksum/script` 가 해시를 들고 있어 스크립트 수정은 `helm upgrade` 만으로 롤아웃 |

## 왜 공유 스토리지가 아니라 rsync 인가

- 공유 스토리지(NFS 등)는 **스토리지 장애 = 전 워커 정지**라 스토리지 자체의 HA 가 필요해지고, 태스크마다 뜨고 지는
  KubernetesExecutor 워커가 매번 네트워크 스토리지를 읽는 I/O 가 붙는다.
- rsync 는 워커가 **자기 노드의 로컬 디렉토리**만 읽는다 — 동기화 파드가 죽어도 이미 뿌려진 코드로 워커는 계속 돈다.
- rsync 의 약점은 "사람이 안 치면 노드 간 코드가 어긋난다"는 휴먼 에러다 → 이 차트가 감지·실행을 맡고,
  상태는 파드의 Ready(전 노드 성공)와 로그로 드러낸다.

## values 계약

- `global.*` 은 이 차트에 없다 — `-f values.common.yaml`. 쓰는 것은 `namespace` · `harborRegistry` · `imageTag` · **`nodes`** 다.
- **대상 IP 는 값이 아니라 파생값**이다: `targets.nodeNames` 의 이름을 `global.nodes` 표에서 찾는다(`_helpers.tpl`).
  표에 없는 이름은 렌더가 실패한다 — `source.nodeName` 도 같은 검사를 받는다(틀린 이름이면 nodeAffinity 가 Pending 으로 조용히 멈추기 때문).
- `repoPath` 는 원본(ap)과 사본(s1/s2)이 **같은 경로**다 — 304-airflow 의 `repo.hostPath` 가 모든 노드에서 이 경로를 읽는다.
  ⚠ 304 `repo.hostPath` · Ansible `group_vars/airflow.yml` 의 `airflow_repo_dir` 와 **같은 커밋 규칙**.
- `sync.excludes` 는 Ansible `airflow_repo_sync_excludes` 와 같은 커밋 규칙 — `*.env`(Secret 의 값 원본)·`logs/` 를 빼지 말 것.
- rsync 옵션(`--archive --delete --delay-updates --delete-delay --chmod=Da+rx,Fa+r`)은 values 가 아니라 **스크립트 고정**이다.
  `--delay-updates` 가 빠지면 반쯤 바뀐 트리를 dag-processor 가 파싱해 DAG 이 잠깐 통째로 사라지고, `--chmod` 가 빠지면
  원본의 0700/0600 이 그대로 넘어가 uid 50000 이 못 읽는다(304 README '코드 반영').
- `ssh.keyHostPath` 는 **원본 노드의 root 개인키**를 hostPath(`type: File`)로 넘긴다 — Ansible 이 노드 간 root SSH 에 쓰는 바로 그 키라
  새 자격증명을 만들지 않는다. known_hosts 는 파드가 `/tmp` 에 자기 것을 쓴다(`accept-new` — 고정 IP 의 host-only 망).

### 이 차트가 만들지 않는 것

- 노드 디렉토리(`repoPath`) — Ansible `airflow_repo_prereq` `all`(root:root 0755). hostPath `type: Directory` 라 원본 노드에 없으면 파드가 뜨지 않는다.
- 대상 노드의 `authorized_keys` — Ansible 선행작업이 이미 전제하는 상태(`ssh root@s1` 이 비대화형으로 되면 충분하다).
- Service · Ingress · PVC — 없다. 지켜야 할 상태가 0 이다.

## 설치

```bash
# 이미지 — 새 리포지토리(rsync)라 처음 한 번은 선별 빌드해도 다른 차트의 태그를 깨지 않는다
/project/data_pipeline/scripts/build_and_push.sh v0.1.0 rsync

helm lint 304-airflow-rsync -f values.common.yaml
helm template airflow-rsync ./304-airflow-rsync -f values.common.yaml
helm install airflow-rsync ./304-airflow-rsync -f values.common.yaml -n data-layer

# 확인 — NODE 가 source.nodeName 이고 READY 1/1 이면 전 노드 동기화 성공
kubectl -n data-layer get pod -l app=airflow-rsync -o wide
kubectl -n data-layer logs deploy/airflow-rsync --tail=20      # 노드별 ok / FAIL
```

## 일상 운영

```bash
helm upgrade airflow-rsync ./304-airflow-rsync -f values.common.yaml -n data-layer   # values·스크립트 변경 반영

# DAG 반영 — 원본에 저장하면 끝. 아래는 확인일 뿐이다
kubectl -n data-layer logs deploy/airflow-rsync --tail=5                          # ok <s1 ip> / ok <s2 ip>
for n in s1 s2; do ssh root@$n 'ls /project/data_pipeline/data_layer_airflow/dags | wc -l'; done
```

- **READY 0/1** = 마지막 동기화가 한 노드 이상에서 실패 — 로그의 `FAIL <ip>` 를 본다(노드 다운·SSH 키·`authorized_keys`).
  복구되면 다음 주기에 스스로 따라잡는다. 그동안은 파서와 워커가 다른 코드를 볼 수 있다(304 README '전 노드에 마쳐야 끝난 것이다').
- 루프가 멈추면 heartbeat 가 오래돼 livenessProbe 가 재시작한다(임계 = `2 × intervalSeconds + 300` 초).
- 노드 증설: `global.nodes` 에 추가 → `targets.nodeNames` 에 추가 → `helm upgrade`. 그 노드의 디렉토리는 Ansible `all` 로 먼저 만든다.
- 원본을 옮길 때(`source.nodeName`): 그 노드에 `repoPath` 원본과 `ssh.keyHostPath` 가 있어야 하고, 옛 원본 노드는 `targets` 로 내려간다.

## 주의

- `--delete` 라 **원본 노드의 디렉토리가 비면 대상 노드의 코드도 지워진다.** 스크립트는 `<repoPath>/dags` 가 없으면 SKIP 하지만
  `dags/` 만 남기고 나머지를 지운 상태까지는 막지 못한다 — 원본은 git 체크아웃(`/project/data_pipeline`)이라 복구는 `git checkout` 이다.
- Ansible `sync` 태그를 같이 돌려도 충돌하지 않는다(같은 옵션·같은 결과) — 다만 이제 필요 없다.
- `helm uninstall` 은 안전하다 — 노드의 코드는 hostPath 라 그대로 남고 동기화만 멈춘다(304 워커는 계속 돈다). hook 이 없어 남는 것도 없다.
- 이 파드는 `data-layer` 네임스페이스라 300 의 ClusterRoleBinding 으로 cluster-admin 이지만 API 서버를 부르지 않는다(권한 모델은 CLAUDE.md).
