# 304-airflow — Helm 차트

**Airflow 3 코어.** api-server / scheduler / dag-processor / triggerer(Deployment 4종) + 메타DB 초기화 Job.
executor 는 **KubernetesExecutor** 라 태스크마다 파드가 뜬다. 메타DB 는 303-postgres 의 CNPG(`-rw`),
태스크 로그는 Hadoop WebHDFS, DAG·커스텀 패키지는 **노드 로컬 `repo.hostPath` 아래의 디렉토리들(`repo.dirs`)을
읽기 전용 hostPath 로 `AIRFLOW_HOME` 아래 같은 이름에 하나씩 마운트한다**(이미지에 굽지 않는다 —
Dockerfile 은 `requirements.txt` 설치가 전부다).
정본은 rsync 원본이고 노드의 것은 3노드에 뿌린 복제본이라 **지켜야 할 상태가 0 — 이 차트에는 PVC 가 없다.**
4종의 자유 스케줄도 그 덕이지만 무조건은 아니다: `type: Directory` 라 디렉토리가 없는 노드에서는 파드가 뜨지 않는다.

| 오브젝트 | 이름 | 역할 |
|---|---|---|
| Secret | `airflow-env` | `AIRFLOW__*` 설정 일체 + 메타DB DSN + 원격 로깅 커넥션. 초기화 Job·코어 4종·태스크 파드가 공유 |
| ConfigMap | `airflow-pod-template` | KubernetesExecutor 태스크 파드 원형 (키 `pod_template.yaml`) |
| Job | `airflow-init` | `db migrate` + 초기 관리자 계정 — helm hook(post-install,post-upgrade). **코어 4종 '뒤'에 돈다** (아래 '주의') |
| Deployment + Service + Ingress | `airflow-apiserver` | 브라우저 UI/REST(`http://data-layer-airflow`) 이자 내부 Execution API(:8080) |
| Deployment | `airflow-scheduler` | 태스크 파드를 찍는 주체 — 코어 4종 중 유일하게 원형을 마운트 |
| Deployment | `airflow-dag-processor` | DAG 파싱 전담(파싱 사고가 스케줄링 루프를 멈추지 않게) — **코드를 실제로 여는 유일한 상주 컴포넌트** |
| Deployment | `airflow-triggerer` | deferrable 오퍼레이터용 — 랩에서는 `replicas: 0` |

⚠ Service 이름 `airflow-apiserver` 와 그 포트는 **내부 계약**이다 —
`AIRFLOW__CORE__EXECUTION_API_SERVER_URL` 이 이 이름을 가리킨다. 외부(인그레스) 이름으로 바꾸면
파드 → VIP → 인그레스 → 파드로 우회해 인그레스 장애가 곧 태스크 정지가 된다.

## values 계약

- `global.*` 은 **이 차트에 없다** — 저장소 루트 `values.common.yaml` 이 유일한 정의처다
  (`-f values.common.yaml`). 여기서 쓰는 것은 `namespace` · `harborRegistry` · `imageTag` ·
  `ingressClassName` · `hosts.airflow` · `postgres.clusterName`/`port`/`databases.airflow` ·
  `secrets.postgresUser`/`postgresPassword` 다. (로그가 MinIO 에서 HDFS 로 옮겨간 뒤 `minioEndpoint`
  와 `secrets.minio*` 는 이 차트가 더 이상 참조하지 않아 `values.schema.json` 의 required 에서도 빠졌다.)
- **`repo.hostPath` / `repo.dirs` / `airflowHome` 은 이 차트 소유다.** `dirs` 의 이름 하나가
  `<repo.hostPath>/<이름>` → `<airflowHome>/<이름>` 마운트 하나가 된다(compose 시절 볼륨과 같은 모양).
  `repo.hostPath` 는 Ansible `airflow_repo_prereq` 가 만드는 디렉토리와 **글자 그대로 같아야** 하고
  (301-kafka 의 `kafka.data.path` ↔ `kafka_prereq` 와 같은 결), `airflowHome` 은
  `AIRFLOW__CORE__DAGS_FOLDER`(`<airflowHome>/dags`)·`PYTHONPATH` 의 단일 출처다 — Secret 이 이 값에서
  파생시키므로 경로를 따로 적지 않는다(어긋날 방법을 없앤다).
- ⚠ **`airflowHome`(`/opt/airflow`) 자체는 마운트하지 않는다.** AIRFLOW_HOME 은 airflow 가 `airflow.cfg`
  와 `logs/` 를 쓰는 자기 홈이라, `readOnly` 로 통째로 덮으면 이미지가 넣어 둔 것이 가려지고 기동조차
  하지 못한다. compose 도 같은 이유로 하위 디렉토리만 각각 붙였다.
- ⚠ **`dirs` 에 `logs` 를 넣지 말 것** — 로그는 WebHDFS 로 나가므로 마운트가 필요 없고, `readOnly` 로
  덮으면 dag-processor 가 `/opt/airflow/logs` 에 못 써서 CrashLoop 이 된다. `config`·`plugins` 도 원본에
  없는 디렉토리라 넣으면 `type: Directory` 에 걸려 파드가 아예 뜨지 않는다(compose 는 없으면 빈
  디렉토리를 만들어 줬지만 hostPath 는 만들어 주지 않는다).
- **이미지 태그는 `global.imageTag` 다.** 재빌드 사유가 `requirements.txt` 변경뿐이라 다른 이미지와 주기가
  같다 — `global.imageTag` 를 쓰지 않는 스택은 303-postgres(CNPG 웹훅) 하나뿐이다.
- Airflow 전용 시크릿(`fernetKey`·`apiSecretKey`·`jwtSecret`·`admin*`)도 이 차트 소유다 — 다른 차트가
  쓰지 않는다. 공유되는 메타DB 자격증명만 `global.secrets` 에 있다(개발 평문 규약은 300 과 같다).
  WebHDFS 접속값(`webhdfs.hosts`/`port`/`user`)도 지금은 이 차트만 쓰므로 여기 있다 — 파이프라인이
  HDFS 를 직접 읽게 되면 그때 `global` 로 올린다.
- **`_helpers.tpl` 에는 값 '변환'이 끼는 조합만 둔다** — `postgresHost`(clusterName+namespace →
  rw Service FQDN) · `sqlAlchemyConn`(계정·포트·DB → DSN, 비밀번호 urlquery) 둘뿐이다.
  그 외는 전부 템플릿에 직접 명시한다 — 이미지 주소(레지스트리+태그 단순 연결)·라벨·envFrom 도
  헬퍼로 감싸지 않는다: 헬퍼로 한 겹 감싸면 값을 확인하려고 파일을 왕복해야 하고 얻는 것이 없다.
- **코드 마운트는 네 곳이다** — dag-processor(파일을 여는 유일한 상주 컴포넌트) · 태스크 파드 원형
  (직렬화본이 아니라 DAG '파일'을 다시 파싱한다) · scheduler(executor 가 LocalExecutor 로 바뀌면 그 순간
  필수라 미리 붙여 둔다) · triggerer(커스텀 Trigger 클래스가 `PYTHONPATH` 로 잡힐 자리). **api-server 에는
  붙이지 않는다** — UI 의 Code 탭은 메타DB 의 직렬화본을 읽으므로 파일이 필요 없고, 붙이면 노출면만 넓어진다.
- 값 하나가 여러 자리에 들어가는 곳: `apiserver.port` → containerPort · Service · Ingress 백엔드 ·
  Execution API URL / `global.hosts.airflow` → Ingress host · `AIRFLOW__API__BASE_URL` · 300 의
  `AIRFLOW_UI_URL`. 어긋나면 로그인 화면까지는 뜨는데 인증 직후 리다이렉트가 튄다.
- **DAG 이 읽는 Variable/Connection 도 이 차트가 만든다** — Secret `airflow-env` 의 `AIRFLOW_VAR_*`/`AIRFLOW_CONN_*`
  (env 백엔드는 메타DB 보다 먼저 조회되므로 초기화 Job 순서와 무관하다). Variable 4종(`collector_crypto_key`·
  `collector_db_query`·`collector_kafka_config`·`collector_snapshot_config`)과 Connection 3종(`collector_db`·
  `collector_kafka`·`data_node_ssh`)이며, 비파생 값은 values 의 `collector.*`/`secrets.dataNodePassword`,
  접속값은 global 파생(`collector_db` 호스트 = `airflow.postgresHost`, `collector_kafka` = `airflow.kafkaBootstrap`,
  크립토 키 = `global.secrets.collectorCryptoKey`)이다 — 구 `scripts/airflow.conf` + `register_airflow_*.sh` 의 승계.
  ⚠ `cdc_seed_loader` 의 `cdc_mysql`/`cdc_oracle`/`cdc_postgres`/`cdc_mssql` 은 여기 없다(400-test-rdb 자격증명) — UI 에서 등록한다.
- **`resources.requests` 는 당분간 주석 처리돼 있다**(코어 4종 + 초기화 Job; 태스크 파드 원형의 128Mi 는 그대로).
  노드 여유가 없어(ap CPU 95%, s1 메모리 96% 요청) api-server 의 1Gi 가 어느 노드에도 들어가지 않아서다 —
  301-hadoop 과 같은 임시 조치이고 대가는 BestEffort QoS(메모리 압박 시 먼저 evict)다. 여유가 생기면 주석을 푼다.
- `values.schema.json` 이 필수 키·형식을 렌더 시점에 강제한다 — 구 "default 없는 변수 = tfvars 강제" 승계.

### 이 차트가 만들지 않는 것

- **공용 `data-layer-env` / `data-layer-secrets`** (300 소유). Terraform 판 Secret 에 있던
  `CDM_OBJSTORE_*` 4키와 `CDM_TZ` 는 **뺐다** — 공용 오브젝트가 이미 같은 값을 주므로 두 벌을 두면
  조용히 갈라진다. envFrom 순서가 `data-layer-env` → `data-layer-secrets` → `airflow-env` 라
  키가 겹치면 Airflow 자체 설정이 이긴다.
- **ServiceAccount / RBAC** — 300 의 ClusterRoleBinding 하나가 default SA 에 권한을 준다
  (scheduler 가 태스크 파드를 만들고 지우는 근거).
- **메타DB `airflow`** — 303-postgres 의 Database CR 이 만든다.

## Terraform 에서 사라진 것

| 구 장치 | Helm 판 |
|---|---|
| `image_tag_slug` (Job 이름에 태그를 박아 불변 spec 을 우회) | `helm.sh/hook-delete-policy: before-hook-creation` — 실행 직전에 Helm 이 옛 Job 을 지운다 |
| `computed_fields` (Job 라벨은 서버가 채운다고 선언) | 불필요 — Helm 은 렌더 결과를 적용할 뿐 서버가 채운 필드를 대조하지 않는다 |
| `depends_on` (Secret/ConfigMap → 워크로드) | kind 설치 순서(Helm 이 Secret·ConfigMap 을 Deployment 보다 먼저 적용한다) |
| `depends_on` (init Job → 코어 4종) | **대체되지 않았다 — 순서가 뒤집혔다.** post-* 훅이라 Job 이 코어 4종 뒤에 돈다(아래 '주의'). 대신 Helm 은 훅 Job 의 **완료를 기다린다** — 구 `depends_on` 은 '먼저 생성'까지였다 |
| `outputs.tf` | `templates/NOTES.txt` |
| `secrets.auto.tfvars` | `values.yaml` 의 `secrets.*` + `values.common.yaml` 의 `global.secrets` |
| `nonsensitive(sha256(...))` 해시 local | `checksum/airflow-env`(scheduler 는 `checksum/pod-template` 추가) = 렌더 결과 `sha256sum` |

## 설치

전제(순서대로):
1. **300-data-layer-base** 설치 완료 — 네임스페이스·공용 ConfigMap/Secret·파드 생성 권한.
2. **303-postgres** 설치 완료 — 메타DB `airflow`(없으면 초기화 Job 이 대기하다 실패한다).
3. **Ansible `airflow_repo_prereq`** — 스케줄 가능한 **모든 노드**에 `/data/airflow-repo`(root:root 0755)
   + 코드 rsync: `bin/start_airflow_repo_prereq.sh <Ansible 저장소 절대경로> all`. ⚠ `type: Directory` 라 경로가 없는 노드에 스케줄되면 그 파드는 기동하지 못한다
   (조용히 "DAG 0개"가 되는 대신 그 자리에서 멈추게 하려는 것이다 — 아래 '코드 반영').
   컨테이너는 UID 50000 으로 **읽기만** 하므로 쓰기 권한은 주지 않는다.
4. **Harbor 이미지** — `airflow:<global.imageTag>` push 완료
   (`/my_project/data_pipeline/scripts/build_and_push.sh <global.imageTag> airflow`).
   다시 빌드하는 것은 `requirements.txt` 가 바뀔 때뿐이다.
5. **Hadoop** — WebHDFS 활성(`dfs.webhdfs.enabled`, 기본 true) + `logs.remoteBaseFolder` 경로를 **`webhdfs.user`
   소유로** 미리 만든다. HDFS 는 `dfs.permissions.enabled=true` 이고 `/` 가 hadoop:supergroup 755 라 user `airflow`
   는 최상위에 디렉토리를 만들 수 없다 — 없으면 업로드가 조용히 실패한다.
   ```bash
   kubectl -n data-layer exec hadoop-namenode-0 -- hdfs dfs -mkdir -p /airflow-logs
   kubectl -n data-layer exec hadoop-namenode-0 -- hdfs dfs -chown airflow:supergroup /airflow-logs
   curl "http://<네임노드>:9870/webhdfs/v1/airflow-logs?op=GETFILESTATUS"      # owner: airflow 면 된다
   ```
   ⚠ 없어도 설치·기동은 성공한다 — 업로드 실패가 태스크를 죽이지 않아 **로그만 조용히 사라진다**.

```bash
helm lint 304-airflow -f values.common.yaml                            # 문법 + 스키마 검사
helm template airflow ./304-airflow -f values.common.yaml              # 미리보기 (클러스터 접근 없음)
helm install airflow ./304-airflow -f values.common.yaml -n data-layer --timeout 10m

# 확인
kubectl -n data-layer logs job/airflow-init                            # migrate + 계정 생성 로그
kubectl -n data-layer get deploy,job,svc,ing -l app.kubernetes.io/name=airflow
# http://data-layer-airflow 로그인 (airflow / airflow)
```

초기화 Job 의 예산은 **스크립트 대기 루프 300s < `activeDeadlineSeconds` 480s < helm `--timeout` 10m**
순서로 닫혀 있다(301-kafka 토픽 Job 과 같은 규약). helm 기본 `--timeout` 은 5m 이라 그대로 두면
303-postgres 기동을 기다리다 걸릴 수 있으므로 위 install/upgrade 명령에 **`--timeout 10m` 을 덧붙인다**.
Job 은 480s 에 스스로 끝나므로 helm 이 포기한 뒤에도 백그라운드에서 계속 도는 일은 없다.

## 일상 운영

```bash
helm template airflow 304-airflow -f values.common.yaml | kubectl diff -f -    # 라이브와 대조
helm upgrade airflow ./304-airflow -f values.common.yaml -n data-layer --timeout 10m   # 값 변경 반영

kubectl -n data-layer get pods -l app.kubernetes.io/component=worker           # 실행 중인 태스크 파드
```

- **DAG 반영에 `helm upgrade` 는 없다** — 코드 수정 → 3노드 rsync → `dagRefreshInterval`(30초) 안에
  재스캔이다(아래 '코드 반영'). 재빌드·태그 변경·롤아웃은 `requirements.txt` 가 바뀔 때만 한다.
- Secret 이나 파드 원형이 바뀌면 `checksum/*` 어노테이션이 따라 바뀌어 자동 롤아웃된다 —
  `rollout restart` 는 필요 없다.
- 성공한 태스크 파드는 사라지고 **실패한 파드는 남는다**(`DELETE_WORKER_PODS_ON_FAILURE=False`) —
  `kubectl logs` 로 원인을 본 뒤 직접 지운다(기동 자체가 실패하면 HDFS 에 아무것도 올라가지 않는다).
- `parallelism`(10) × 태스크 파드 requests(128Mi)가 클러스터에 실제로 필요한 메모리다 —
  넘치면 태스크가 실행되는 대신 Pending 으로 쌓인다.

### 코드 반영 — 3노드 rsync (재빌드가 아니다)

원본은 `/my_project/data_pipeline/data_layer_airflow`, 목적지는 노드마다 `/data/airflow-repo` 다
(양쪽 끝의 `/` 를 빠뜨리면 `--delete` 가 한 단계 안쪽에 트리를 다시 만든다).

정본은 Ansible 롤이다 — 손으로 칠 때도 옵션을 줄이지 않는다(아래 ⚠ 가 이유다).

```bash
# 권장: 롤이 소유한 제외 목록·옵션을 그대로 쓴다 (group_vars/airflow.yml)
bin/start_airflow_repo_prereq.sh <Ansible 저장소 절대경로> sync

# 손으로 할 때 — 위 롤과 같은 옵션이다
for n in ap s1 s2; do
  rsync -a --delete --delay-updates --delete-delay --chmod=Da+rx,Fa+r \
    --exclude '.git/' --exclude 'logs/' --exclude '__pycache__/' --exclude '*.pyc' \
    --exclude '*.env' --exclude '.env*' \
    /my_project/data_pipeline/data_layer_airflow/ root@$n:/data/airflow-repo/
done
kubectl -n data-layer logs deploy/airflow-dag-processor --tail=20   # 30초 안에 재스캔 로그
```

- ⚠ **`*.env` 를 빼지 말 것.** `airflow.env` 는 Secret `airflow-env` 의 값 원본(fernet 키·메타DB·데이터 노드 SSH 비밀번호)이다.
  파드는 그 값을 Secret 으로 받으므로 노드에 사본이 있을 이유가 없고, 한 번 흘리면 3노드 디스크에 평문으로 남는다.
- ⚠ **`--chmod=Da+rx,Fa+r` 를 빼지 말 것.** `-a` 는 원본의 모드를 그대로 옮긴다 — 원본 루트가 `0700` 이면
  노드의 `/data/airflow-repo` 도 `0700` 이 되어 Ansible 이 준 `0755` 를 조용히 되돌리고, UID 50000 이 진입조차
  못 해 **파드는 뜨는데 DAG 만 0개**가 된다(`0600` 인 파일도 같은 식으로 사라진다). `a+rx`/`a+r` 은 더하기만 한다.
- ⚠ **`--delay-updates` 를 빼지 말 것.** dag-processor 가 30초마다 폴더를 훑는데 기본 rsync 는 파일을
  하나씩 갈아 끼우므로, 절반만 동기화된 순간을 파싱하면 **DAG 이 잠깐 통째로 사라진다**(그 창에 걸린
  스케줄은 그대로 유실된다). `--delay-updates` 는 전송을 다 받은 뒤 한꺼번에 옮겨 그 창을 없앤다.
  더 확실히 하려면 옆 디렉토리에 받고 심볼릭 링크를 갈아 끼운다 — 다만 그 방식을 쓰면 **마운트를 링크가
  아니라 부모 디렉토리로 잡아야** 컨테이너가 링크를 따라간다. 링크 자체를 마운트하면 컨테이너 안에서는
  깨진 링크로 보인다 — `dirs` 의 각 이름이 곧 마운트 대상이므로 링크로 갈아 끼우는 방식과는 맞지 않는다.
- ⚠ **전 노드에 마쳐야 끝난 것이다.** 태스크 파드는 자기가 스케줄된 노드의 디렉토리를 읽으므로 일부
  노드만 동기화된 동안에는 파서와 실행 주체가 서로 다른 코드를 볼 수 있다 — 같은 이미지를 쓴다는 사실은
  파이썬 환경만 보장하지 코드를 보장하지 않는다.
- `requirements.txt` 가 바뀌었으면 rsync 로 끝나지 않는다 — 패키지는 이미지 안에 있으므로
  재빌드 → `global.imageTag` 변경 → `helm upgrade` 로 롤아웃한다.
  ⚠ `global.imageTag` 는 301-kafka·302-monitoring 이 함께 쓰는 값이다. 태그를 올릴 때
  airflow 만 선별 빌드하면 나머지 차트가 **없는 태그**를 가리키게 되어 다음 upgrade 에서 ImagePullBackOff 가 된다
  → 새 태그로는 `build_and_push.sh <새 태그>` 를 이름 인자 없이 돌려 전 이미지를 함께 push 한다.

### DAG 가 0개다 (진단 순서)

```bash
# ① 노드에 경로가 있는가 — 없으면 파드가 아예 못 뜬다(Pending / hostPath type check failed)
for n in ap s1 s2; do ssh root@$n 'stat -c "%n %U:%G %a" /data/airflow-repo'; done   # root:root 755
# ② UID 50000 이 읽을 수 있는가 — 0755 면 읽기는 되지만 rsync 가 원본의 좁은 모드를 옮겨 올 수 있다
kubectl -n data-layer exec deploy/airflow-dag-processor -- ls /opt/airflow/dags
# ③ rsync 가 그 노드까지 갔는가 — 파드가 어느 노드에 떴는지부터 본다
kubectl -n data-layer get pod -l app=airflow-dag-processor -o wide
for n in ap s1 s2; do ssh root@$n 'ls /data/airflow-repo/dags | wc -l'; done
# ④ DAGS_FOLDER·PYTHONPATH 가 마운트와 맞는가 — 둘 다 airflowHome 파생이라 어긋나면 누군가 경로를 박은 것이다
kubectl -n data-layer exec deploy/airflow-dag-processor -- printenv AIRFLOW__CORE__DAGS_FOLDER PYTHONPATH
kubectl -n data-layer logs deploy/airflow-dag-processor --tail=50   # 파싱/import 에러는 여기에만 남는다
```

## 주의

- **실행 '중' 태스크의 라이브 로그는 UI 에 보이지 않는다**(워커 로컬 파일이라 업로드 후에야 나타난다)
  — 그 사이에는 `kubectl logs` 를 쓴다.
- 이미지에 apache-hdfs 프로바이더가 없으면 원격 로깅 3키는 **에러 없이 무시**되고 로그만 사라진다.
- **초기화 Job 은 코어 4종 '뒤'에 돈다**(post-install/post-upgrade 훅). 신규 설치 때 api-server·scheduler·
  dag-processor 는 스키마 없는 메타DB 를 보고 CrashLoopBackOff 로 돌다가 Job 이 끝난 뒤 회복한다 —
  정상 경로이고, 그동안 `kubectl get pods` 는 붉게 보인다.
- ⚠ **그래서 이 차트에 `--wait` / `--atomic` 을 쓰면 안 된다.** helm 은 `--wait` 이면 릴리스 리소스가
  Ready 가 된 '다음' post 훅을 돌리는데, 마이그레이션 전에는 Ready 가 될 수 없어 서로를 기다리다
  `--timeout` 에 걸린다(`--atomic` 은 그 뒤 롤백까지 한다).
- `helm uninstall` 은 이 스택에서는 안전한 편이다 — PVC 가 없어 메타DB(303)와 로그(HDFS)가 그대로 남고,
  코드(`/data/airflow-repo`)도 hostPath 라 볼륨 수명주기가 노드에 있어 지워지지 않는다.
  다만 **훅 리소스는 릴리스 매니페스트가 아니라서 Job `airflow-init` 과 그 파드가 네임스페이스에 남는다**
  (`hook-delete-policy` 가 `before-hook-creation` 뿐 — 다음 설치 직전에만 정리된다).
  깨끗이 지우려면 `kubectl -n data-layer delete job airflow-init` 을 한 번 더 친다.
- `triggerer.replicas: 0` 은 랩 메모리 절약용 임시값이다. deferrable 오퍼레이터를 쓰기 시작하면 1 로
  올린다 — 아니면 태스크가 영원히 deferred 에 머문다.

## 추후 ArgoCD

이 차트는 그대로 ArgoCD Application 의 `source.path` 가 될 수 있고, sync-wave 는 300 → 303 다음이다.
⚠ 다만 **초기화 Job 을 그대로 두면 안 된다** — ArgoCD 는 `post-install` 훅을 PostSync 로 매핑하는데,
PostSync 는 Sync 리소스가 전부 Healthy 가 된 뒤에만 돌고 코어 4종은 마이그레이션 전에 Healthy 가
될 수 없다(위 '주의'의 `--wait` 교착과 같은 형태다). ArgoCD 로 옮기는 커밋에서 이 Job 을
`argocd.argoproj.io/hook: PreSync` 로 바꾸고, 그때 Secret `airflow-env` 도 함께 앞으로 당긴다.
