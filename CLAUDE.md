# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 저장소 개요

kubeadm 3노드 랩 클러스터 위에 **플랫폼은 Terraform 스택, 워크로드는 Helm 차트**로 쌓는 IaC 저장소.
클러스터: ap=192.168.56.38(control-plane) · s1=192.168.56.39 · s2=192.168.56.40 — k8s v1.34.4, containerd 2.2.1, Cilium 1.20.1(kube-proxy 대체, host-only NIC eth1).
도구 핀: Terraform 1.15.8 / Helm 3.19.0 / 프로바이더 kubernetes 2.38.0 · helm 3.2.0 · harbor 3.10.21. 노드 정본은 Ansible `host.yml` 의 `ansible_host`.

- **Terraform 은 100~200 다섯 스택뿐**(100-base · 101-metallb · 102-ingress · 103-cnpg · 200-harbor). **300 이후는 전부 Helm 차트** 15개
  (300 · 301-elasticsearch/hadoop/kafka/minio/neo4j · 302 · 303 · 304-airflow · 304-airflow-rsync · 305 · 306 · 307 · 308-spark · 400). ArgoCD 는 없다.
- 이미지(`build_and_push.sh` 의 27종)와 값 원천 문서(`.env` · `data_layer_airflow/airflow.env`)는 `/project/data_pipeline` 소유. 매니페스트·env 조립은 이 저장소 몫.
  노드 선행작업(디렉토리·hosts·containerd 레지스트리 신뢰·Longhorn OS 준비)은 `/project/Infrastructure-as-Code-Ansible` 담당.
- **공통값의 단일 출처는 루트 `values.common.yaml` 의 `global.*`** — `namespace` `harborRegistry`(`data-layer-harbor:80`) `imageTag`(`v0.1.0`) `ingressClassName` `nodes` `kafka` `hadoop` `alloy` `prometheus`
  `postgres` `minioEndpoint` `minioBuckets` `neo4jBoltUri` `hosts` `ingressVip` `secrets`. 차트 values.yaml 에는 `global` 이 없고 **모든 helm 명령에 `-f values.common.yaml`** 을 붙인다
  (안 주면 `values.schema.json` 이 렌더 전에 막는다 — 스키마가 없는 301-hadoop 만 `nil pointer evaluating ... .hadoop` 으로 죽는다).
- 스토어 위치: **Kafka = 301-kafka**(STS, hostNetwork, 오퍼레이터 없음) · **HDFS = 301-hadoop**(HA, hostNetwork — Iceberg 데이터 레이크 `/warehouse`) · **MinIO = 301-minio**(ClusterIP, 버킷 `config`·`airflow-logs`)
  · **Neo4j = 301-neo4j**(ClusterIP, `global.neo4jBoltUri`=`bolt://neo4j.data-layer.svc.cluster.local:7687`) · **Elasticsearch = 301-elasticsearch**(STS, hostNetwork — 소비자 없음) · **PostgreSQL = 103-cnpg + 303-postgres**(CNPG)
  · **Spark = 308-spark**(작업 창구 파드 하나, 클러스터 없음). 전부 K8s 안이다.
- 파이프라인은 300 의 공용 ConfigMap `data-layer-env` 로 붙는데 **접속 주소는 값이 아니라 파생값**이다 — `KAFKA_BOOTSTRAP`(`global.kafka.brokers` × `ports.client` 노드 IP 목록 — 브로커는 Service 가 없다) ·
  `KAFKA_BOOTSTRAP_PLAINTEXT` · `SCHEMA_REGISTRY_URL` · `KAFKA_CONNECT_URL` · `COLLECTOR_DB_HOST`/`PLATFORM_PG_DSN`(`global.postgres.clusterName` → CNPG `-rw` FQDN) · `CDM_OBJSTORE_ENDPOINT/BUCKET`(`minioEndpoint`·`minioBuckets.config`) ·
  `ICEBERG_WAREHOUSE`(`hdfs://<nameservice>/warehouse`)·`ICEBERG_CATALOG_URI/DB_NAME` · `PLATFORM_NEO4J_URI/DATABASE` · `KAFKA_UI_URL`·`AIRFLOW_UI_URL`·`GRAFANA_URL`. 주소 문자열을 values 에 복사하지 않는다.
- **설정 ConfigMap 은 그것을 읽는 차트가 소유한다** — 301-kafka `kafka-config`·`kafka-jmx-exporter`, 302 `alloy-config`·`prometheus-config`·`grafana-datasource`, 304 `airflow-pod-template`, 304-airflow-rsync `airflow-rsync-script`,
  307 `hdfs-client-config`, 308 `spark-defaults`·`spark-hadoop-config`. 300 은 공용 `data-layer-env`·Secret 만 소유한다. **301-elasticsearch·308-spark 는 공용 ConfigMap/Secret 을 아예 읽지 않는다.**

## 스택: 번호 디렉토리 = 독립 스택 (번호 = 적용 순서, 제거는 역순, 같은 301 끼리는 순서 무관)

### 플랫폼 — Terraform (100~200, 각자 state)

- `100-base` — local-path-provisioner 0.0.37(**기본 StorageClass**) + Longhorn 1.11.3(복제 2, `/data/longhorn`). `longhorn` 을 쓰는 것은 노드를 옮겨 다니는 단일 인스턴스(301-minio · 301-neo4j · 302 prometheus/grafana)뿐.
  `local-path` 는 200-harbor(PVC 5개) · 303(복제는 CNPG 가) · 400. 301-kafka/hadoop/elasticsearch 는 프로비저너 없는 자기 StorageClass + 정적 local PV.
  **`nodeDownPodDeletionPolicy: delete-both-statefulset-and-deployment-pod`** 는 301-minio/neo4j 노드 장애 페일오버의 전제라 지우지 말 것. 노드 OS 선행은 Ansible `longhorn_prereq`.
- `101-metallb` — MetalLB 0.16.1 차트만. **VIP 풀은 갖지 않는다**(`IPAddressPool`/`L2Advertisement` 는 이 차트가 만드는 CRD 라 같은 스택에 두면 첫 `plan` 이 타입을 못 찾는다). ⚠ `frrk8s.enabled = false` 필수(기본 `true` 면 노드마다 FRR 컨테이너).
- `102-ingress` — VIP 풀 둘(`ingress-vip` .240 · `postgres-vip` .241, /32 + `autoAssign: false` + L2Advertisement) + ingress-nginx 4.15.1(replicaCount 2, required podAntiAffinity, `externalTrafficPolicy: Local`).
  **101 apply 후에만 plan 통과.** `helm_release` 는 CR 두 개에 `depends_on`(풀이 없으면 EXTERNAL-IP 를 영영 못 받아 timeout). VIP 요청은 `metallb.io/loadBalancerIPs` 어노테이션. Ingress 오브젝트는 각 앱 차트 소유.
  `kubernetes_manifest` + `templatefile` 을 쓰는 곳은 이 스택(MetalLB CR)뿐.
- `103-cnpg` — CloudNativePG **오퍼레이터+CRD 만**(차트 0.29.0 = 오퍼레이터 1.30.0, ns `cnpg-system`). Cluster/Database CR 은 303 소유 → "103 apply 후에만 303 install 가능"(`helm template` 은 CRD 를 검증하지 않는다).
  오퍼레이터 이미지는 차트 기본(ghcr.io) — Harbor 대상이 아니다. PodMonitor/Grafana 대시보드는 꺼 둔다(302 는 hand-rolled Prometheus, CRD 없음).
- `200-harbor` — goharbor 차트 1.18.4(Harbor 2.14, HTTP). `expose.type: ingress` — Service·Ingress 를 차트가 만들고 push 필수 어노테이션 넷(`proxy-body-size: "0"` · `proxy-request-buffering: "off"` · `proxy-read/send-timeout` 600 · `ssl-redirect: "false"`)을 values 에 둔다
  ("노출은 앱 차트 소유" 규약의 유일한 예외). 프로바이더 둘(helm · harbor — `data-layer` 프로젝트 public). `externalURL`(`http://data-layer-harbor`)은 접속 주소와 일치해야 push 가 된다.
  컴포넌트 7개 전부 `harbor_node_name`(**s2**) 에 nodeSelector(PVC 5개가 local-path 라 어차피 노드 고정, 약 41Gi). `terraform_data.core_probe_relax` 가 apply 뒤 `kubectl patch` 로 core probe 완화(실행 머신에 kubectl 필요, revision 마다 재실행).
  `secrets.auto.tfvars`(`harbor_admin_password`)를 쓰는 유일한 스택 — Ansible `buildkit_registry_password` 와 같아야 한다.

### 워크로드 — Helm 차트 (300 이후, 릴리스 네임스페이스 `data-layer`)

- `300-data-layer-base` — **ns `data-layer` + ConfigMap `data-layer-env`(63키) + Secret `data-layer-secrets`(Opaque 8키) + Secret `<clusterName>-app-user`(basic-auth, `cnpg.io/reload`) + ClusterRoleBinding `data-layer-default-admin` 의 소유자.**
  워크로드·이미지·values.yaml 없음(전부 `global`). `_helpers.tpl` 6종(`svcSuffix` · `kafkaBootstrap` · `kafkaBootstrapPlaintext` · `postgresHost` · `postgresDsn` · `icebergCatalogUri`).
  ⚠ release 는 **`-n default`**(`data-layer` 는 이 차트가 만든다 — `--create-namespace` 는 "already exists" 충돌). ⚠ `helm uninstall` = **네임스페이스째 삭제**. 값 변경 후 소비 워크로드 재기동은 사람이(다른 릴리스라 checksum 없음).
- `301-hadoop` — HDFS HA: ZooKeeper ×3 · JournalNode ×3 · NameNode ×2(+ZKFC) · DataNode ×3 = STS 4종이 `templates/hadoop-statefulset.yaml` 한 파일. hostNetwork(Service 없음) + 정적 local PV `hadoop-local` 11개(`claimRef` 로 ordinal ↔ `global.hadoop.<구성요소>.nodeNames[N]` 고정, NameNode 는 ap·s1).
  `Parallel` + **`OnDelete`**(NameNode 는 Standby → Active 순). ConfigMap 없음 — core-site/hdfs-site/zoo.cfg 는 STS 파일 안의 define(`hadoop.writeConf` 등)이 만들고 **hook Job 도 그 define 을 쓴다**(STS 파일을 지우면 Job 렌더가 깨진다).
  노드 디렉토리 `/data/hadoop-*` 는 Ansible `hadoop_prereq` 가 root:root **2770**(s2 의 namenode 디렉토리는 의도적으로 빈 채) — 차트의 `dfs.datanode.data.dir.perm=770` 과 한 쌍. `clusterId`(`CID-data-layer`)는 데이터가 있으면 변경 금지.
  hook Job `hadoop-dirs`(post-install/upgrade)가 `/warehouse` 를 `global.hadoop.warehouse.user` 소유로 멱등 생성(720s 대기 < 900 < **`--timeout 15m`**); 추가 경로는 `hadoop.extraDirs`, `hadoop.dirs: {}` 키는 지우지 말 것(Job 이 참조).
  소비자는 307 warehouse 컨슈머(libhdfs)와 308-spark. `resources.requests` 주석 처리. ⚠ **README · NOTES.txt · values.schema.json · _helpers.tpl 이 없는 유일한 차트.**
- `301-kafka` — STS `kafka` + schema-registry · kafka-ui(Ingress `global.hosts.kafkaUi`) · kafka-exporter. **오퍼레이터 없음**(Strimzi 는 hostNetwork 미지원). 장애는 Kafka 복제(RF 3)로 — hostNetwork(광고 주소 = 노드 IP) + 정적 local PV `kafka-local`(data 10Gi + metadata 2Gi).
  **브로커 ID = ordinal = `global.kafka.brokers` 인덱스**, `claimRef` 로 kafka-N 은 brokers[N] 에만. 앞 `controllers`(3)개가 controller+broker 겸용(정적 쿼럼) → 증설은 표 뒤에, 축소는 뒤에서. **`OnDelete`** — 사람이 한 대씩 URP 0 확인(README '롤링 재기동').
  ConfigMap `kafka-config`(`server.properties.tpl`)·`kafka-jmx-exporter`(`files/jmx-exporter.yaml`) + `checksum/*`(OnDelete 라 재기동 없이 updateRevision 만). 힙·javaagent 는 기동 스크립트 안 `export`(env 로 옮기면 exec 한 CLI JVM 이 9404 를 다시 열어 죽는다).
  **브로커 Service 없음**(STS `serviceName` 도 생략). 토픽 16종은 hook Job `kafka-topics`(780s < 900 < **`--timeout 15m`**). 노드 디렉토리 `/data/kafka-broker`·`/data/kafka-controller`(root:root 2770)는 Ansible `kafka_prereq` = `global.kafka.data/metadata.path`.
  ⚠ `helm uninstall` 은 PVC 를 남기고 PV 는 지운다 → **재설치 전 PVC 를 먼저 삭제**(pv-protection; Retain 이라 디스크 데이터는 유지). schema-registry 의 `SCHEMA_REGISTRY_CUB_KAFKA_MIN_BROKERS`(=브로커 수)는 `_schemas` 가 RF 1 로 굳는 사고 방지 — 지우지 말 것.
- `301-minio` — 단일 인스턴스 S3: Deployment(`Recreate`) + PVC `longhorn` 20Gi + ClusterIP `minio`:9000, `MINIO_BROWSER=off`. 소형 오브젝트 전용(`config` 설정·스키마, `airflow-logs` Airflow 태스크 로그 — ILM `expireDays.airflowLogs` 30) — 데이터 레이크가 아니다.
  장애는 **Longhorn 복제**로(kafka/hadoop 과 반대 전략): `nodeDownPodDeletionPolicy` + values `tolerationSeconds`(60) + 옮겨 갈 노드의 instance-manager 셋이 맞물려야 한다 — 절차는 `RUNBOOK.md`.
  env 는 `envFrom` 예외(`MINIO_ROOT_*` ← 공용 `CDM_OBJSTORE_*` secretKeyRef). hook Job `minio-buckets` 가 `global.minioBuckets` 전부 생성 + ILM(420s < 480 < **`--timeout 10m`**; global 에 없는 `expireDays` 키는 렌더 실패). `config` 시드는 `mc pipe` 수동(README '버킷'). ⚠ `helm uninstall` 은 PVC 삭제 = 데이터 소실.
- `301-neo4j` — Deployment 1(`Recreate`) + PVC `neo4j-data`(`longhorn` 20Gi) + ClusterIP `neo4j`(bolt 7687 / http 7474). Ingress 없음(Browser 는 port-forward). Community 라 앱 복제 없음 → Longhorn 복제 + `tolerationSeconds` 60(301-minio 와 같은 페일오버 전제).
  env 는 `secretKeyRef`(`PLATFORM_NEO4J_USER/PASSWORD` → `NEO4J_AUTH`); **`global.secrets.neo4jUser` 는 `"neo4j"` 고정**(아니면 렌더 `fail`). 비밀번호는 빈 볼륨 첫 기동에만 반영(이후는 `ALTER USER`). `ports.bolt` ↔ `global.neo4jBoltUri` 같은 커밋.
  소비자는 307 graph 컨슈머(300 `PLATFORM_NEO4J_*` 경유) — URI 변경 시 `helm upgrade data-layer-base` + graph 컨슈머 재기동은 사람이. hook 없음. `resources.requests` 유지(메모리 2Gi = heap+pagecache 와 함께 조정). ⚠ `helm uninstall` 은 PVC 삭제 = 데이터 소실.
- `301-elasticsearch` — STS `elasticsearch` ×`len(nodeNames)`(ap/s1/s2), hostNetwork(9200/9300) + 정적 local PV `elasticsearch-local`(`/data/elasticsearch` 20Gi, Retain, `claimRef` 고정) + ClusterIP `elasticsearch`:9200 만. `Parallel` + **`OnDelete`** + required podAntiAffinity.
  ConfigMap 없음(점 이름 env 가 곧 설정, `xpack.security.enabled=false`). 장애는 ES 복제(마스터 과반 + replica 1 — `number_of_replicas` 0 금지)로, 파드는 노드를 옮기지 않는다. 노드 디렉토리는 Ansible `elasticsearch_prereq`(root:root 2770) = values `data.path`.
  **소비 차트 없음**(300 에 관련 키 없음). hook 없음. `resources.requests` 유지. ⚠ `helm uninstall` 은 PVC 를 남긴다 → 재설치 전 삭제.
- `302-monitoring` — alloy(DaemonSet, hostNetwork, privileged) + prometheus(`nodeNames` s1) + grafana(`nodeNames` s2, Ingress `global.hosts.grafana`/`prometheus`), 둘 다 `Recreate` + `longhorn` PVC. ConfigMap 3종 + `checksum/config`(alloy·prometheus)·`checksum/datasource`(grafana) → `helm upgrade` 만으로 롤아웃
  (alloy·prometheus 이미지는 `FROM` 한 줄, 설정 변경에 재빌드 없음; Grafana 대시보드 JSON 만 이미지에). 스크랩 잡 6개(alloy-node · alloy-cadvisor · kafka-exporter · kafka-jmx · postgres · cnpg-operator) 전부 kubernetes_sd — neo4j/elasticsearch/spark/minio 잡은 없다.
  grafana 만 `envFrom` + `GF_SERVER_ROOT_URL` ← `GRAFANA_URL` configMapKeyRef. 300 이 먼저 있어야 한다(SD 권한 없으면 `/targets` 가 **조용히** 빈다). ⚠ `helm uninstall` 은 PVC 둘 삭제.
- `303-postgres` — CNPG Cluster `data-layer-postgres`(instances 2, `nodeNames` s1/s2 + required antiAffinity, `local-path` 40Gi — install 후 변경 불가). DB 3종의 부트스트랩 정본: `data_layer`(initdb + `postInitApplicationSQL` — timescaledb, 스키마 `data_pipeline`, 테이블 `collect_job`·`realtime_source`·`data_lineage`(하이퍼테이블)) + `Database` CR `airflow`·`iceberg_catalog`.
  앱 계정은 superuser 가 아니다(임시 관리는 `kubectl exec ... psql -U postgres`). 계정 Secret `<clusterName>-app-user` 는 300 소유(305·308 도 secretKeyRef). **`imageTag`(`16.15-v0.1.0`)는 `global.imageTag` 를 쓰지 않는 유일한 값**(CNPG 웹훅이 태그에서 PG 메이저를 읽는다).
  외부 접속은 `-external` LoadBalancer → VIP `192.168.56.241:5432`(selector `instanceRole: primary`), `-metrics` 9187 은 302 가 긁는다. 백업 없음(`RUNBOOK.md` — `max_slot_wal_keep_size=-1` 이라 replica 방치 시 WAL 이 디스크를 채운다).
  ⚠ 권한 모델·`enableServiceLinks` 규약의 문서화된 예외(CNPG 가 SA/Role·파드 템플릿 소유). ⚠ `helm uninstall` = Cluster CR 삭제 = PVC 까지 삭제.
- `304-airflow` — Airflow 3, KubernetesExecutor: apiserver(Ingress `global.hosts.airflow`)/scheduler/dag-processor/triggerer(`replicas: 0`) + 메타DB 초기화 Job. **코드(DAG·패키지)는 이미지에 없다** — 노드 `/project/data_pipeline/data_layer_airflow`(`repo.hostPath`) 의 `repo.dirs`(dags·collector·processor·publisher·utils)를
  `/opt/airflow/<dir>` 에 읽기 전용 hostPath(`type: Directory` — 경로 없는 노드에선 파드가 아예 안 뜬다; scheduler·dag-processor·triggerer·태스크 파드 원형 `airflow-pod-template` 이 마운트, apiserver 는 안 한다). 반영은 rsync(304-airflow-rsync) → dag-processor 재스캔이라 `helm upgrade` 가 끼지 않고, 재빌드 사유는 `requirements.txt` 뿐이라 공용 `global.imageTag`.
  **태스크 로그는 301-minio `s3://airflow-logs`**(`REMOTE_BASE_LOG_FOLDER` ← `global.minioBuckets.airflowLogs`, Connection `minio_logs` = `conn_type: aws` + `endpoint_url: global.minioEndpoint`). Secret `airflow-env` = `AIRFLOW__*` + Variable 4종 + Connection 4종(`collector_db`·`collector_kafka`·`data_node_ssh`·`minio_logs`); `cdc_*` Connection 은 400 자격증명이라 UI 등록.
  `_helpers.tpl` 3종(`postgresHost`·`sqlAlchemyConn`·`kafkaBootstrap`). envFrom 순서 `data-layer-env` → `data-layer-secrets` → `airflow-env`(겹치면 Airflow 쪽이 이긴다). ⚠ 초기화 Job 은 `post-install,post-upgrade` 훅이라 코어 **뒤**에 돈다 — 신규 설치 때 코어 CrashLoopBackOff 는 정상,
  그래서 **`--wait`/`--atomic` 금지, `--timeout 10m`**(300s < 480). 노드 디렉토리(root:root 0755, 컨테이너 UID 50000 읽기)는 Ansible `airflow_repo_prereq`. `helm uninstall` 안전(PVC 없음, hook Job `airflow-init` 은 남는다).
- `304-airflow-rsync` — 304 의 코드 디렉토리를 노드 간에 맞추는 Sync Pod(Deployment 1, `Recreate`, `source.nodeName`(ap) nodeAffinity, 이미지 `rsync`). 원본 `repoPath` 를 읽기 전용 hostPath 로 inotify 감시 → `sync.debounceSeconds`(5)·`sync.intervalSeconds`(1800)마다 `targets.nodeNames`(IP 는 `global.nodes` 파생, 없는 이름은 렌더 실패)에 root SSH rsync
  (`ssh.keyHostPath` `/root/.ssh/id_ed25519` 를 hostPath `File` 로). 옵션 `--archive --delete --delay-updates --delete-delay --chmod=Da+rx,Fa+r --timeout=60` 고정, 제외 목록 `sync.excludes` 는 Ansible 과 같은 커밋. `dags/` 가 없으면 `--delete` 를 막고 not-ready 로 멈춘다.
  ConfigMap `airflow-rsync-script`(`checksum/script`). Ready = 마지막 동기화 전 대상 성공, 루프 정지는 heartbeat liveness 로 재시작. 308 의 `spark_jobs` 도 이 파드가 맞춘다. Service·PVC·hook 없음 — `helm uninstall` 안전.
- `305-api` — Deployment(**replicas 1, 스키마 `const`** — `/quality/apply` 가 매퍼 파드를 delete 하므로 둘이면 같은 매퍼를 두 번 죽인다) + ClusterIP 8090 + Ingress `global.hosts.api`(`proxyBodySize` 50m · `proxyReadTimeout` 300 = read/send).
  docker socket 조작은 K8s API 어댑터로 대체, 권한은 300 의 바인딩 하나, 대상 ns 는 `fieldRef`. DB 계정은 `<clusterName>-app-user` secretKeyRef. Grafana 를 서버사이드로 부르므로 `hostAliases` = `global.ingressVip`(파드가 `data-layer-*` 이름을 풀 수 있는 유일한 경로).
- `306-cdc` — kafka-connect(Debezium) Deployment ×`replicas`(2 — 노드 메모리 제약) + **required podAntiAffinity** + ClusterIP `cdc-connect`(`global.kafka.connectPort` 8083 = 300 `KAFKA_CONNECT_URL`). `BOOTSTRAP_SERVERS` 는 공용 `KAFKA_BOOTSTRAP` 을 configMapKeyRef(checksum 없음 — 표 변경 시 300 upgrade 후 `rollout restart`).
  상태는 Kafka 내부 토픽 3종(`storageTopics` — 바꾸면 커넥터가 사라진 것처럼 보이거나 스냅샷을 다시 뜬다). 커넥터 등록은 차트 밖(REST). startupProbe 300s(플러그인 스캔), `terminationGracePeriodSeconds` 90, `replicationFactor` ≤ 브로커 수.
- `307-pipeline` — cdm-mapper 8종(`mapper.modules` range — 라벨 `app=cdm-mapper` + `cdm.mapper/module` 은 305 DQ 적용과의 계약) + 컨슈머 3종(`consumer.kinds` rdb/graph/warehouse — 이미지 + '코드가 읽는 이름 → 공용 키' valueFrom 번역표; warehouse 는 `hdfs: true` 로 `hdfs-client-config` 를 `/etc/hadoop/conf` 에 + `HADOOP_USER_NAME`=`global.hadoop.warehouse.user` + `checksum/hdfs-client`;
  graph 는 `NEO4J_*` ← `PLATFORM_NEO4J_*`) + `cdm-lineage-consumer` + tcp-socket-collector(hostNetwork, replicas 1 `Recreate`, `tcpSocket.nodeNames` nodeAffinity — 후보가 둘 이상이면 장비 쪽 대상 IP 가 전부를 커버해야 한다). PVC·probe 없음(이상 감지 = 컨슈머 lag).
  타임아웃 사슬: 300 `DATA_QUALITY_RESTART_DRAIN_TIMEOUT`(180, 305 가 `gracePeriodSeconds` 로 실어 보낸다) + 재기동 대기 60 = 240 < 305 `proxyReadTimeout`(300) — 하나를 올리면 같이. `terminationGracePeriodSeconds`(300)는 사슬 밖.
- `308-spark` — Spark on K8s **작업 창구**: Deployment `spark-workbench` 1(`sleep infinity`, `kubectl exec` 로 spark-submit — Service·Ingress·PVC·hook 없음), executor 는 잡마다 파드(권한 = 300 바인딩). `nodeNames` nodeAffinity(`global.nodes` 검사).
  PySpark 코드는 읽기 전용 hostPath `/project/data_pipeline/data_layer_airflow/spark_jobs`(304 `repo.hostPath` 아래라 304-airflow-rsync 가 맞춘다, `type: Directory`). ConfigMap `spark-defaults` + `spark-hadoop-config`(307 `hdfs-client-config` 와 같은 내용의 사본) + `checksum/*`.
  카탈로그 `cdm` = 303 `iceberg_catalog` JDBC(계정은 `<clusterName>-app-user` secretKeyRef → 기동 시 `/tmp/spark-conf` 사본에 append), warehouse = `hdfs://<nameservice>/warehouse`(307 warehouse 컨슈머 pyiceberg 와 같은 곳 — `catalog` 이름이 다르면 서로 테이블이 안 보인다).
  `jdbc.schema-version=V1` 금지(pyiceberg 모델에 없는 컬럼). `spark.kubernetes.driver.pod.name` 이 창구 이름으로 박혀 있어 cluster 모드면 덮어쓴다. `helm upgrade` = 창구 재생성 = 열린 exec 세션과 잡 종료(긴 잡은 `nohup`). `resources.requests` 주석 처리. `helm uninstall` 안전.
- `400-test-rdb` — CDC 소스 RDB 4종(cdc-oracle · cdc-mssql · cdc-postgres · cdc-mysql): STS 1 + ClusterIP + 초기화 ConfigMap(`files/*-initdb.*` 를 `tpl`) + 자기 Secret `test-rdb-secrets`(`secrets.cdcSourceDbPassword` = `data_pipeline/.env` 의 `CDC_SOURCE_DB_PASSWORD`).
  300번대의 **입력을 흉내 내는 테스트 픽스처**라 400 — 300번대 오브젝트를 하나도 참조하지 않는다(공용 ConfigMap/Secret 도). Service 이름·포트·계정/DB 이름이 Debezium 커넥터 JSON·Airflow `cdc_*` 커넥션과의 대외 계약이고 **초기화 스크립트가 이 스택의 본체**다
  (셋은 이미지 첫 기동 훅 — 빈 볼륨에서만 → 고치면 PVC `data-cdc-<db>-0` 삭제; mssql 만 hook Job `cdc-mssql-init`, `backoffLimit 3`+`OnFailure` 인 유일한 hook — **`--timeout 20m`**). `storageClass: local-path`. NodePort 없음(port-forward). ⚠ `helm uninstall` 은 PVC 를 남긴다.

**스택 간 의존성은 코드에 없다.** 순서는 번호가 담당하고 사이에 Terraform/Helm 이 모델링 못 하는 수동 단계가 있다:
Ansible 선행작업(`longhorn_prereq`·`kafka_prereq`·`hadoop_prereq`·`elasticsearch_prereq`·`airflow_repo_prereq`·`etc_hosts`) → 이미지 빌드/push(200 뒤, 300 전) → MinIO `config` 시드(301-minio 뒤) → 커넥터 등록·`cdc_*` Airflow 커넥션(306/400 뒤).
`/warehouse`·버킷은 hook Job 이 만든다. 차트 사이의 값 전달은 오브젝트 **이름**(ConfigMap/Secret/Service)과 `values.common.yaml` 의 같은 원본으로 — `terraform output` 은 Terraform 스택 사이에만.

## 명령어

```bash
# Terraform 스택 (100~200) — 스택마다 각자 init 부터, 루트에서는 -chdir
terraform -chdir=100-base init && terraform -chdir=100-base plan
terraform -chdir=100-base fmt -check && terraform -chdir=100-base validate

# Helm 차트 (300 이후) — 항상 -f values.common.yaml, 릴리스 네임스페이스는 data-layer (300 만 default)
helm lint 301-kafka -f values.common.yaml                                   # 문법 + values.schema.json
helm template kafka ./301-kafka -f values.common.yaml                       # 렌더 확인 (클러스터 접근 없음)
helm template kafka ./301-kafka -f values.common.yaml | kubectl diff -f -   # 라이브와 대조
helm template kafka ./301-kafka -f values.common.yaml | kubectl apply --dry-run=server -f -   # API 서버 검증 (CR 을 가진 303 은 필수)
helm install data-layer-base ./300-data-layer-base -f values.common.yaml -n default          # 300 만 default
helm install kafka ./301-kafka -f values.common.yaml -n data-layer --timeout 15m             # hook Job 예산

# 이미지 빌드/push (200-harbor apply 뒤, 300번대 설치 전 — Terraform/Helm 밖 수동 단계)
/project/data_pipeline/scripts/build_and_push.sh <TAG>              # 27종 전부 → data-layer-harbor:80/data-layer/<name>:<TAG>
/project/data_pipeline/scripts/build_and_push.sh <TAG> <이름>...    # 선별 (303 operand 는 이 방식으로 16.15-<TAG> postgres)

# 노드 선행작업 (Ansible 저장소 bin/ — 2인자: <Ansible 절대경로> <all|태그>)
bin/start_kafka_prereq.sh / start_hadoop_prereq.sh / start_elasticsearch_prereq.sh / start_longhorn.sh <경로> all
bin/start_airflow_repo_prereq.sh <경로> all      # 디렉토리 + rsync   / sync → 수동 DAG 반영만
bin/start_server_configuration.sh <경로> etc_hosts
```

| 차트 | 릴리스 이름 | 비고 |
|---|---|---|
| 300-data-layer-base | `data-layer-base` | `-n default`, `--create-namespace` 금지 |
| 301-hadoop / 301-kafka | `hadoop` / `kafka` | `--timeout 15m` |
| 301-minio | `minio` | `--timeout 10m` |
| 301-elasticsearch / 301-neo4j | `elasticsearch` / `neo4j` | hook 없음, 기본 timeout |
| 302-monitoring / 303-postgres | `monitoring` / `postgres` | 303 은 103 apply 이후 |
| 304-airflow | `airflow` | `--timeout 10m`, `--wait`/`--atomic` 금지 |
| 304-airflow-rsync | `airflow-rsync` | `source.nodeName` 의 원본 디렉토리·개인키가 hostPath 라 없으면 파드가 안 뜬다 |
| 305-api / 306-cdc / 307-pipeline / 308-spark | `api` / `cdc` / `pipeline` / `spark` | — |
| 400-test-rdb | `test-rdb` | `--timeout 20m` |

**`terraform apply`/`destroy` 와 `helm install`/`upgrade`/`uninstall` 은 사용자가 직접 실행한다.** Claude 는 파일 작성과 `plan`/`fmt`/`validate`/`helm lint`/`helm template`/`--dry-run=server` 수준 검증까지만 하고 실행 명령어는 안내로 제공할 것.
`global.imageTag` 를 올릴 때는 이름 인자 없이 전부 push 한다 — 선별 빌드하면 나머지 차트가 **없는 태그**를 가리켜 다음 upgrade 에서 ImagePullBackOff(303 `imageTag` 만 별도 규칙).

## 규칙 (이 저장소의 비자명한 결정들)

### 공통

- **버전은 전부 정확 고정.** `>=`, `~>` 금지 — CLI(`required_version`)·프로바이더·서드파티 차트 모두. 자체 차트 `Chart.yaml` `version` 은 전부 0.1.0(`appVersion` 없음), 올릴 때는 사람이 명시적으로. 새 버전을 박기 전에 레지스트리(registry.terraform.io, 차트 index.yaml)에서 실존 확인.
- **리소스가 없는 프로바이더는 선언하지 않는다.** 100/101/103 은 helm 하나, 102 는 helm + kubernetes(MetalLB CR), 200 은 helm + harbor.
- **환경마다 달라야 하는 값은 default 를 주지 않는다** — Terraform 은 `variables.tf` default 없이 `terraform.tfvars` 강제, Helm 은 `values.schema.json` `required`(차트가 실제로 참조하는 `global` 키만).
- 파일 분리: Terraform 은 `versions.tf` `providers.tf` `variables.tf` `terraform.tfvars`(`secrets.auto.tfvars`) + 컴포넌트별 tf — **`main.tf` 금지**. Helm 은 `Chart.yaml` `values.yaml` `values.schema.json` `.helmignore` `templates/*.yaml` `templates/NOTES.txt` `README.md`(+ 운영 절차가 있으면 `RUNBOOK.md` — 301-minio·303).
- 주석은 한국어, "무엇"이 아니라 **"왜"**. 한 주제 2~4줄, 반복·회고·자명한 서술 금지. **섹션 배너는 아래 형식 하나**(기준: `200-harbor/variables.tf` · `301-kafka/templates/kafka-statefulset.yaml`). 개별 리소스/필드에는 배너 대신 `# ...` 한두 줄.

```hcl
# ===============================================
# [섹션명]
#
# 핵심 설명
# ===============================================
```

- `description` 은 한 줄 사실 서술(`<<-EOT` 금지). `helm_release` values 는 인라인 `yamlencode()`, 한 화면을 넘으면 별도 파일.
- 최소주의: remote backend · atomic · modules · ArgoCD 는 필요가 생기기 전까지 도입하지 않는다.

### Helm 차트 규약

- **`global.*` 은 차트에 정의하지 않는다.** 두 차트 이상이 같은 값을 보면 `global` 로 올린다(300 의 ConfigMap 이 참조하는 값 포함). 소비처가 300 하나뿐인 리프(`secrets.neo4jPassword`·`grafanaAdmin*`·`dataLayerApiKey`·`minioBuckets.config`)는 이름을 바꿔도 300 렌더는 통과하고 소비 워크로드만 조용히 깨진다.
- **접속 주소는 값이 아니라 파생값** — 원본(노드 표·clusterName·namespace·포트)에서 `_helpers.tpl` 이 조립한다. **`_helpers.tpl` 은 값 '변환'이 끼는 조합만**(FQDN, `urlquery` DSN, 표 → 목록); 단순 연결(레지스트리+태그)·정적 블록(라벨·envFrom)은 템플릿에 직접. 정본은 304 README '차트 규약'.
- **공용 ConfigMap/Secret 의 키는 '읽는 이름'당 하나.** 다른 이름으로 읽는 워크로드는 300 에 사본 키를 두지 않고 자기 `env:` 에 `valueFrom` 으로 번역한다(301-minio `MINIO_ROOT_*`, 302 `GF_SERVER_ROOT_URL`, 305 `COLLECTOR_DB_USER/PASSWORD`, 306 `BOOTSTRAP_SERVERS`, 307 `*_PG_DSN`·`NEO4J_*`·`TCP_SOCKET_*`).
  종류별 튠 노브(`CDM_CONSUMER_<종류>_BATCH_*`·`*_LOG_LEVEL`)는 값이 같아도 독립 노브라 합치지 않는다. 사본 키를 지울 때는 **소비 차트 먼저 upgrade, 300 은 나중에**.
- **설정 ConfigMap 과 파드가 같은 릴리스면 `checksum/<이름>: {{ include ... | sha256sum }}`** 을 파드 템플릿에 심어 `helm upgrade` 만으로 롤아웃(302 · 304 · 304-airflow-rsync · 307 warehouse · 308 · 301-kafka — 브로커는 OnDelete 라 updateRevision 표시만). 다른 릴리스(300 을 읽는 306 등)면 README 에 '사람이 재기동'.
- **hook Job**: `spec.template` 불변은 `helm.sh/hook-delete-policy` 로 푼다 — `before-hook-creation,hook-succeeded`(301-kafka·hadoop·minio: 성공하면 스스로 사라짐) / `before-hook-creation`(304 `airflow-init`·400 `cdc-mssql-init`: 남는다).
  대기 예산은 **스크립트 루프 < `activeDeadlineSeconds` < helm `--timeout`** 으로 닫고 명령에 `--timeout` 을 적어 둔다(기본 5m). 실패 로그를 남기려면 `backoffLimit: 0` + `restartPolicy: Never` 한 쌍(400 mssql 만 3+OnFailure 예외). hook 리소스는 `helm uninstall` 이 지우지 않는다 — 남은 Job 은 `kubectl delete job`.
- **`helm uninstall` 의 결과는 차트마다 다르다 — README '주의' 를 먼저 읽는다.** 네임스페이스째(300) / PVC 삭제 = 데이터 소실(301-minio · 301-neo4j · 302 · 303) / PVC 잔존 + 재설치 전 삭제 필요(301-kafka · 301-hadoop · 301-elasticsearch — pv-protection) / PVC 잔존(400) / 안전(304 · 304-airflow-rsync · 305 · 306 · 307 · 308).
  PVC 선택 삭제는 `app.kubernetes.io/name` 까지 걸어서 — `part-of=data-layer` 만으로 지우면 다른 차트의 PVC 까지 잡힌다.
- **StatefulSet 의 `serviceName`·`podManagementPolicy` 는 불변** → `kubectl delete sts <이름> --cascade=orphan` 후 `helm upgrade`(같은 라벨의 파드를 재기동 없이 입양).
- **hostNetwork + 정적 local PV 패턴(301-kafka · 301-hadoop · 301-elasticsearch)**: 자기 StorageClass(no-provisioner, WaitForFirstConsumer, Retain) + 노드마다 PV 를 range 로 찍고 `claimRef` 로 STS PVC 이름(`<volume>-<sts>-<ordinal>`)에 미리 묶는다.
  `podManagementPolicy: Parallel`(쿼럼 교착 방지) + `updateStrategy: OnDelete` + `dnsPolicy: ClusterFirstWithHostNet` + `fsGroup: 0` + `fsGroupChangePolicy: OnRootMismatch`. 노드 디렉토리는 Ansible 이 root:root **2770**(setgid — `0770` 이면 재기동마다 전체 chown). `Released` PV 는 `claimRef.uid` 만 patch(301-kafka README 'PV 재사용').
- **YAML 은 1.1 이다**(helm/kubectl) — 8진수 `0755` 그대로, 셸 `${VAR}` 이스케이프 불필요. Terraform `yamldecode`(1.2)와 반대.
- **`resources.requests` 는 주석 처리한 차트가 있다**(301-hadoop · 304 코어+init · 304-airflow-rsync · 305 · 306 · 307 · 308 · 400 — 노드 2 vCPU/약 3GB 여유 부족, 대가는 BestEffort). 301-kafka · 301-minio · 301-neo4j · 301-elasticsearch · 302 · 303 은 유지. limits 는 어디에도 없고 JVM 은 힙 고정.
- 릴리스 네임스페이스: 300 만 `default`, 나머지 `data-layer`. `helm template` 은 CRD 를 검증하지 않으므로 CR 을 가진 303 은 `--dry-run=server` 로 한 번 더.

### 시크릿

- Terraform: `sensitive = true` + **`secrets.auto.tfvars`**(200-harbor 만, `.example` 동봉). `terraform.tfvars` 에는 시크릿을 넣지 않는다.
- Helm: 공유 자격증명은 `global.secrets`(300 이 Secret 두 개로), 한 차트만 쓰는 것은 그 차트 values `secrets.*`(304 fernet/JWT/admin, 400 소스 DB 비밀번호). 개발 평문 규약(운영 전환 시 SealedSecrets/SOPS). Secret 은 typed 오브젝트(`stringData`)로만, `kubectl create secret` 금지.
- ⚠ **공개 저장소(`github.com/sy0218/Infrastructure-as-Code-Terraform.kubernetes`)이고 `*.tfstate`·`*.auto.tfvars` 를 일부러 gitignore 하지 않는다**(랩 자격증명이라는 운영자 결정). 실계정을 쓰는 순간 `.gitignore` 네 줄을 되살리고 자격증명 전량 교체. `.terraform.lock.hcl` 은 커밋, `.terraform/` 은 무시.

### kubernetes_manifest + templatefile (Terraform — 102-ingress 의 MetalLB CR 뿐)

- 표준형 `manifest = yamldecode(templatefile("${path.module}/manifests/<파일>.yaml.tftpl", {...}))`. **템플릿 1파일 = YAML 문서 1개**(`---` 다중 문서는 plan 실패).
- `yamldecode` 는 YAML 1.2 — **8진수는 `0o755`**(`0755` 는 십진수 755 로 조용히 들어간다). 셸 변수는 `$${VAR}`. `--dry-run=server` 교차검증은 JSON 으로(YAML 재덤프는 `Y` 가 불리언이 된다).
- `for_each` 키는 안정적인 문자열(리스트 인덱스 금지). API 서버가 기본값을 채우는 필드(probe `timeoutSeconds` 등)는 명시(아니면 `unexpected new value ... was null`). 컨테이너 추가는 목록 맨 뒤(위치 병합). Job `spec.template` 불변은 `apply -replace`.

### 쿠버네티스 규약

- 모든 매니페스트에 `namespace: {{ .Values.global.namespace }}`, 공통 라벨 `app.kubernetes.io/part-of: data-layer`(+ `app`·`app.kubernetes.io/name`, 다중 구성요소는 `component`). 선택 삭제할 PVC 에는 `app.kubernetes.io/name` 까지.
- env 기본형은 `envFrom: [configMapRef: data-layer-env, secretRef: data-layer-secrets]` + 워크로드 전용 `env:`. **예외**: 301-minio·301-neo4j(서버가 `MINIO_*`/`NEO4J_*` 접두 env 를 설정으로 해석 → secretKeyRef), 400(픽스처에 플랫폼 자격증명 금지 → 자기 Secret), 미들웨어(301-kafka 브로커 · 301-hadoop · 301-elasticsearch · 302 alloy/prometheus · 308 — 앱 env 불필요).
- **모든 파드 spec 에 `enableServiceLinks: false`**(도커 링크식 Service env 가 설정을 조용히 덮는다 — `SCHEMA_REGISTRY_PORT` 사고). 예외는 303(CNPG 소유).
- **`data-layer` 안의 오브젝트를 `kubectl` 로 직접 수정하지 말 것**(Helm 3-way merge 가 되돌리거나 충돌). 예외는 문서화된 수동 단계뿐(노드 라벨, MinIO 시드, 커넥터/Airflow 커넥션 등록, `--cascade=orphan` 재입양).
- 이미지는 예외 없이 Harbor 경유(`{{ .Values.global.harborRegistry }}/data-layer/<name>:{{ .Values.global.imageTag }}`), `imagePullPolicy: IfNotPresent`. 서드파티(prometheus·alloy·minio·neo4j·elasticsearch·test-rdb 4종)도 `FROM` 한 줄 Dockerfile 로 `build_and_push.sh` `IMAGES` 에서 함께(노드 containerd 가 Harbor 만 insecure 신뢰). 태그는 불변(재사용하면 IfNotPresent 라 롤아웃이 조용히 안 일어난다). 예외는 303 `imageTag`.
- nodeSelector 금지(예외: 200-harbor). **노드 후보는 values `nodeNames` + nodeAffinity**(302 · 303 · 304-airflow-rsync · 307 tcp-socket · 308 — `global.nodes` 에 없는 이름은 렌더 실패). hostNetwork + local PV 는 PV 의 nodeAffinity 가 고정. 한 노드에 하나만 = required podAntiAffinity(`kubernetes.io/hostname` — 303 · 306 · 301-elasticsearch · 301-kafka · 301-hadoop).
- hostNetwork 파드(301-kafka · 301-hadoop · 301-elasticsearch · 302 alloy · 307 tcp-socket)는 `dnsPolicy: ClusterFirstWithHostNet` 필수. 포트는 노드 전체에서 유일(`ss -lnt` 로 설치 전 확인).
- Deployment 가 RWO PVC 를 쓰면 `strategy: Recreate`(301-minio · 301-neo4j · 302 — RollingUpdate 는 Multi-Attach 로 죽는다).

### 외부 노출 (Ingress 기본 · 비-HTTP 는 VIP 또는 hostNetwork)

- **브라우저용 HTTP 는 Ingress** — 진입점은 VIP 하나(.240), 주소 `http://<호스트명>`(포트 없음), **호스트 기반**으로 가른다. 정본은 `global.hosts`(kafkaUi · airflow · api · grafana · prometheus)와 200 `harbor_host`; 300 은 같은 값으로 `*_URL` 을 조립한다. 추가/변경은 Ansible `data_layer_vip_dns_names` 와 같은 커밋.
  Ingress 는 각 앱 차트 소유(301-kafka kafka-ui · 302 grafana/prometheus · 304 apiserver · 305 api), `ingressClassName: {{ .Values.global.ingressClassName }}` 필수(빠지면 조용히 404). 예외: 200-harbor 는 차트가 Ingress 도 만든다.
- **비-HTTP**: 303 = 전용 VIP .241:5432(NodePort 는 표준 포트를 못 지킨다) / 301-kafka·301-hadoop·301-elasticsearch = hostNetwork(클라이언트가 브로커·DataNode·노드가 광고한 주소로 다시 붙는다) / tcp-socket-collector·alloy = hostNetwork. 400 소스 RDB 와 301-minio·301-neo4j 는 ClusterIP 뿐(사람은 port-forward) — **NodePort 를 만들지 않는다.**
- **200-harbor 의 host 는 이미지 이름의 첫 마디** — `data-layer-harbor:80/data-layer/<name>:<tag>`, **`:80` 생략 불가**(`.`/`:` 없는 첫 마디는 docker.io 네임스페이스로 정규화). 노드 containerd 는 같은 문자열의 `certs.d/<이름>/hosts.toml` 을 찾는다. 인그레스 뒤라 IP 로 우회 pull 은 불가(404).
- 호스트명은 `data-layer-<서비스>`, 밑줄·`.local` 금지(RFC 1123 / mDNS). `<앱>_nodeport` 류 값을 다시 만들지 말 것(경로가 둘로 갈라진다). `externalTrafficPolicy: Local` 은 인그레스 컨트롤러 Service 에만.
- 노드 `/etc/hosts` 는 Ansible `etc_hosts` 롤이 만든다 — VIP 계열(harbor·kafka-ui·airflow·api·grafana·prometheus → .240, 전환 주체 MetalLB). 파드 안에서는 이 이름이 안 풀린다(CoreDNS 는 노드 hosts 를 안 본다) → 예외는 305 의 `hostAliases`(`global.ingressVip`) 하나.
- **내부 호출은 ClusterIP 이름/포트 그대로**(grafana→prometheus, scheduler→apiserver, api→매퍼) — 외부 이름으로 바꾸면 인그레스 장애가 곧 태스크 정지.
- 업로드 경로가 있는 Ingress 에는 `proxy-body-size`(기본 1m → 413), 오래 걸리는 동기 엔드포인트에는 `proxy-read-timeout`(기본 60초 → 504) — 현재 305 뿐, 값의 근거는 307 과의 타임아웃 사슬.

### 권한 모델 — 워크로드별 RBAC 을 두지 않는다

1인 운영이라 권한 오브젝트는 **300 의 ClusterRoleBinding `data-layer-default-admin` 하나**(`data-layer` 의 `default` SA → `cluster-admin`). 워크로드에 `serviceAccountName` 을 쓰지 않고 SA/Role/RoleBinding/ClusterRole 을 새로 만들지 않는다(예외: 303 — CNPG 가 스스로 만든다, 지우면 인스턴스가 멈춘다).
"RBAC 을 껐다"가 아니다 — apiserver 는 `Node,RBAC` 이라 바인딩이 없으면 305 DQ 적용·304 태스크 파드 생성·308 executor 생성이 403, prometheus `/targets` 는 조용히 빈다. 신뢰 경계가 생기면 이 파일을 지우고 워크로드별 Role 로.

### 같은 커밋에서 함께 바꿔야 하는 값 (저장소 밖과의 커플링)

| 이 저장소 | 함께 가는 곳 |
|---|---|
| `global.nodes[].ip` · `global.kafka.brokers[].ip` | Ansible `host.yml` 의 `ansible_host` |
| `global.harborRegistry`(`data-layer-harbor:80`) · 200 `harbor_host`/`externalURL`/harbor 프로바이더 URL | Ansible `containerd_insecure_registries`·`buildkit_registry`, `build_and_push.sh` 의 `REGISTRY` |
| 200 `harbor_admin_password`(secrets.auto.tfvars) | Ansible `buildkit_registry_password` |
| 102 `ingress_vip` · `global.ingressVip` | Ansible `ingress_vip` |
| 102 `postgres_vip` · 303 `externalIp` | — (둘이 같아야 한다) |
| `global.hosts.*` · 200 `harbor_host` | Ansible `data_layer_vip_dns_names`, 접속 PC 의 hosts |
| `global.kafka.data/metadata.path` | Ansible `group_vars/kafka.yml` |
| 301-hadoop 노드 디렉토리 경로 · `dfs.datanode.data.dir.perm=770` | Ansible `group_vars/hadoop.yml`(경로 · `hadoop_data_mode: '2770'`) |
| 301-elasticsearch `data.path` | Ansible `group_vars/elasticsearch.yml` 의 `elasticsearch_data_dir` |
| 304 `repo.hostPath` · 304-airflow-rsync `repoPath`/`sync.excludes` · 308 `jobs.hostPath`(그 아래) | Ansible `group_vars/airflow.yml` 의 `airflow_repo_dir`/`airflow_repo_sync_excludes` |
| `global.minioEndpoint` · `global.neo4jBoltUri` | 301-minio Service 이름/`ports.api` · 301-neo4j Service 이름/`ports.bolt`(저장소 안 커플링) |
| `global.imageTag` · 303 `imageTag` | `build_and_push.sh <TAG>`(303 은 `16.15-<TAG> postgres` 로 별도 push) |
| `global.secrets.collectorCryptoKey` · 400 `secrets.cdcSourceDbPassword` | `data_pipeline/.env` · `data_layer_airflow/airflow.env`(값 원천 문서) |
| 301-kafka `topics` · 307 `mapper.modules` · 308 `catalog`(`cdm`) · 400 Service 이름/포트/계정 | `data_pipeline` 의 kafka.conf TOPICS · 매퍼 모듈 파일 · `cdm_consumer_warehouse` 의 `SqlCatalog("cdm")` · Debezium 커넥터 JSON |

## 커밋 컨벤션 ([COMMIT_CONVENTION.md](COMMIT_CONVENTION.md))

- `type(scope): subject` — 제목은 한국어, 50자 이내, 마침표 없음, 명령형("추가" ⭕ / "추가함" ❌). 한 커밋에는 한 가지 변경만. type: feat / fix / docs / refactor / style / test / chore / ci, scope 는 스택 번호(`301-kafka`, `102-ingress`) 위주.
- 원격은 GitHub(`sy0218/Infrastructure-as-Code-Terraform.kubernetes`, main). tfstate 가 커밋 대상이므로 Terraform apply 뒤 state 변경분도 같은 흐름에서 커밋한다(`chore: ... state 최신화`).

## 알려진 문서 잔재 (코드가 정본이다)

- **304-airflow 의 `README.md`·`Chart.yaml` 은 태스크 로그를 WebHDFS 로 적고 있다** — 실제는 MinIO `s3://airflow-logs`(위 304 항목). 같은 README 의 `/my_project/...` 는 `/project/...`, 헬퍼 "2개"는 3개.
- 300 `templates/NOTES.txt` 의 "MinIO/Neo4j → Ansible 로 노드에 구성"·"공통 설정 → values.yaml" 은 틀렸다(둘 다 차트, 300 에 values.yaml 없음). 300 README 의 ArgoCD 참조 `/my_project/test/README.md` 는 존재하지 않는다.
- 루트 README 의 디렉토리 트리에는 301-elasticsearch · 301-neo4j · 304-airflow-rsync · 308-spark 가 빠져 있고, `secrets.auto.tfvars # (Git 제외)` 한 줄은 gitignore 정책과 모순이며, hadoop/kafka/minio 의 `helm install` 예시에 `--timeout` 이 없다. 302 README 의 "5개 잡" 은 6개.
- Ansible 저장소의 `data_layer_dns_names: [data-layer-neo4j]`(노드 IP 계열)·`data_layer_vip_dns_names` 의 `data-layer-headlamp` 는 이 저장소에 대응 스택이 없다. `build_and_push.sh` 배너의 "26종" 은 27종.
