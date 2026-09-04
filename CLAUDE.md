# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 저장소 개요

kubeadm 3노드 랩 클러스터 위에 **플랫폼은 Terraform 스택, 애플리케이션은 Helm 차트**로 쌓는 IaC 저장소.
클러스터: ap=192.168.56.38(control-plane), s1=192.168.56.39, s2=192.168.56.40 — k8s v1.34.4, containerd 2.2.1,
CNI Cilium 1.20.1(kube-proxy 대체, host-only NIC eth1). 도구 핀: Terraform 1.15.8 / Helm 3.19.0 /
프로바이더 kubernetes 2.38.0 · helm 3.2.0 · harbor 3.10.21. 노드 정본은 Ansible `host.yml` 의 `ansible_host` 다.

- **디렉토리 이름과 달리 Terraform 은 100~200 뿐이다.** 300 이후(300~307·400)는 **전부 Helm 차트**다
  (Chart.yaml/values.yaml/values.schema.json/templates/NOTES.txt/README.md). ArgoCD app-of-apps 는 예정이고 아직 없다.
- 내용물은 `/project/data_pipeline` 의 docker compose 스택을 쿠버네티스로 옮긴 것이다(문서 곳곳의 `/my_project` 는 구 경로).
  그 저장소가 소유하는 것은 **이미지(Dockerfile 24종)와 값 원천 문서(`.env`·`airflow.env`)** 뿐이고, 매니페스트·env 조립은 이 저장소 몫이다.
  노드 선행작업(디렉토리·hosts·containerd 레지스트리 신뢰·Longhorn OS 준비)은 `/project/Infrastructure-as-Code-Ansible` 이 담당한다.
- **공통값의 단일 출처는 저장소 루트 `values.common.yaml` 의 `global.*`** 이다 — 노드 IP 표(`global.nodes`·`global.kafka.brokers`)·포트·
  네임스페이스·`harborRegistry`(`data-layer-harbor:80`)·`imageTag`·`hosts`·`ingressVip`·`minioEndpoint`·`neo4jBoltUri`·`secrets`.
  각 차트 values.yaml 에는 `global` 이 없고, **모든 helm 명령에 `-f values.common.yaml` 을 붙인다**(안 주면 `values.schema.json` 이 렌더 전에 막는다).
- 스토어 위치: **Neo4j 만 K8s 밖**(노드 로컬 — Ansible 에 설치 롤은 없고 etc_hosts 이름 등록뿐, `global.neo4jBoltUri`=`bolt://192.168.56.38:7687`).
  **MinIO 는 301-minio**(ClusterIP, `global.minioEndpoint`=`http://minio.data-layer.svc.cluster.local:9000`), **Kafka 는 301-kafka**(StatefulSet, hostNetwork,
  오퍼레이터 없음), **PostgreSQL 은 103-cnpg + 303-postgres**(CNPG), **HDFS 는 301-hadoop**(HA, hostNetwork — 304 태스크 로그 저장소).
  구 Ansible 의 kafka/minio/postgres 설치 롤은 전부 퇴역했고 `kafka_prereq`·`hadoop_prereq`·`airflow_repo_prereq`(노드 디렉토리)만 남았다.
- 파이프라인은 300 의 공용 ConfigMap `data-layer-env` 의 접속값으로 붙는데 **접속 주소는 값이 아니라 파생값**이다 — `KAFKA_BOOTSTRAP` 은
  `global.kafka.brokers` × `ports.client` 로 조립한 **노드 IP 목록**(브로커는 hostNetwork 라 Service 가 없다), `COLLECTOR_DB_HOST` 는
  `global.postgres.clusterName` 에서 파생한 CNPG `-rw` Service FQDN, `MINIO_S3_ENDPOINT` 는 `global.minioEndpoint` 다. 주소 문자열을 values 에 복사하지 않는다.
- **설정 ConfigMap 의 소유자**: 300 이 `kafka-config`(server.properties.tpl)·`kafka-jmx-exporter`(`files/jmx-exporter.yaml`)를 만들고 301-kafka 가 마운트한다
  (다른 릴리스라 checksum 롤아웃이 없다 — 어차피 브로커는 OnDelete). 302 는 자기 `alloy-config`·`prometheus-config`·`grafana-datasource` 를 소유한다(같은 릴리스라 checksum 자동 롤아웃).

## 아키텍처: 번호 디렉토리 = 독립 스택

숫자 접두사 디렉토리 하나가 독립된 Terraform 루트 모듈(각자 state) 또는 Helm 차트(각자 release)다. 번호 = 적용 순서, 제거는 역순.
같은 번호(301)는 서로 독립이라 어느 순서로 올려도 된다.

### 플랫폼 — Terraform (100~200)

- `100-base` — local-path-provisioner(0.0.37, **기본 StorageClass**) + Longhorn(1.11.3, 복제 2, `/data/longhorn`). kubeadm 엔 기본 StorageClass 가 없어 지정 없는 PVC 는 Pending 에 걸린다.
  `longhorn` 을 쓰는 것은 노드를 옮겨 다니는 단일 인스턴스(302 prometheus·grafana, 301-minio)뿐이다. `local-path` 인 것은 200-harbor(PVC 5개 전부 — 이미지 정본은 MinIO tar 백업),
  303-postgres(복제는 CNPG 가 앱 레벨에서 — longhorn 이중 복제 회피), 400-test-rdb(매일 다시 채우는 테스트 데이터 — values `storageClass`). 301-kafka·301-hadoop 은
  프로비저너 없는 자기 StorageClass(`kafka-local`/`hadoop-local`) + 정적 local PV 다. **`nodeDownPodDeletionPolicy: delete-both-statefulset-and-deployment-pod`** 는
  301-minio 노드 장애 페일오버의 전제라 지우지 말 것(없으면 죽은 노드의 파드가 Terminating 에 영원히 걸린다). Longhorn 은 노드 OS 선행작업(open-iscsi/multipath/`/data/longhorn`)이
  필요 — Ansible `longhorn_prereq` 롤(Terraform 밖 수동 단계).
- `101-metallb` — MetalLB(0.16.1, 공식 차트). 온프렘이라 `type: LoadBalancer` 에 IP 를 붙여 줄 주체가 없어 그 자리를 채운다. **차트만 설치하고 VIP 대역은 갖지 않는다** —
  `IPAddressPool`/`L2Advertisement` 는 이 차트가 만드는 CRD 라서 같은 스택에 두면 첫 `plan` 이 타입을 못 찾고 죽는다(`kubernetes_manifest` 는 plan 시점에 API 서버에 타입을 물어본다).
  ⚠ `frrk8s.enabled = false` 를 반드시 명시한다 — 차트 기본값이 `true` 라 BGP 백엔드가 서브차트째 딸려 와 노드마다 FRR 컨테이너가 뜬다(이 랩은 L2 만 쓴다).
- `102-ingress` — **VIP 풀 둘**(`ingress-vip` .240 · `postgres-vip` .241, 각각 /32 + `autoAssign: false` + L2Advertisement) + ingress-nginx(4.15.1). **101 이 apply 돼 있어야 plan 이 통과한다**(위 CRD 제약).
  `helm_release` 에 CR 두 개로 `depends_on` 을 반드시 건다: helm 은 LoadBalancer Service 가 EXTERNAL-IP 를 받을 때까지 기다리는데 풀이 없으면 영영 안 나와 timeout 으로 실패한다.
  VIP 요청은 폐기된 `spec.loadBalancerIP` 가 아니라 `metallb.io/loadBalancerIPs` 어노테이션으로 한다. Ingress 오브젝트는 여기서 만들지 않는다 — 각 앱 스택이 자기 노출을 소유한다.
  `postgres_vip` 의 요청자는 303-postgres 의 `-external` Service 이고 값은 303 values `externalIp` 와 같은 커밋 규칙이다. 이 저장소에서 `kubernetes_manifest` + `templatefile` 을 쓰는 곳은 이제 여기(MetalLB CR)뿐이다.
- `103-cnpg` — **CloudNativePG 오퍼레이터(CRD 포함)만 설치한다**(차트 0.29.0 = 오퍼레이터 1.30.0, ns `cnpg-system`). Cluster/Database CR 은 303-postgres 차트 소유 — 여기서는 "103 apply 후에만 303 helm install 가능"으로
  나타난다(`helm template` 은 CRD 검증을 안 해 통과하고 install 이 `no matches for kind Cluster` 로 죽는다). 오퍼레이터 이미지는 **차트 기본(ghcr.io)** 그대로다 — Harbor 재호스팅 대상이 아니고(구 `data_layer_cnpg` 는 없다),
  폐쇄망이면 노드 3대에 `crictl pull` 로 선반입한다. operand(PostgreSQL) 이미지만 Harbor `postgres` 다. PodMonitor/Grafana 대시보드는 반드시 꺼 둔다(302 는 hand-rolled Prometheus — CRD 가 없다).
- `200-harbor` — Harbor 레지스트리(goharbor 차트 1.18.4 = Harbor 2.14, TLS 없는 HTTP). `expose.type` 은 **`ingress`** — Service 와 Ingress 를 차트가 만들고 push 용 필수 어노테이션 넷은 values 의
  `expose.ingress.annotations` 에 둔다("노출은 앱 스택 매니페스트가 소유한다" 규약의 유일한 예외 — 나중에 TLS 로 갈 때 차트 배선을 그대로 쓰기 위함). 프로바이더는 둘(helm·harbor — `data-layer` 프로젝트를 public 으로 만든다).
  `externalURL`(`http://data-layer-harbor`)은 실제 접속 주소와 반드시 일치해야 docker push 가 동작한다. 컴포넌트 7개 전부 `harbor_node_name`(s1) 하나에 nodeSelector 로 모은다(어느 컴포넌트가 죽어도 전체가 멎으므로 흩어 얻는 것이 없고
  PVC 5개가 local-path 라 어차피 노드 고정 — 대가는 그 노드에 약 41Gi). `terraform_data.core_probe_relax` 가 apply 뒤 `kubectl patch` 로 harbor-core 의 probe 를 완화한다(차트 values 로 못 바꾼다 — 실행 머신에 kubectl 필요, release revision 이 바뀔 때마다 재실행).
  `secrets.auto.tfvars`(`harbor_admin_password`)를 쓰는 유일한 스택이고, Ansible `buildkit_registry_password` 와 글자 그대로 같아야 한다.

### 워크로드 — Helm 차트 (300 이후)

- `300-data-layer-base` — **네임스페이스 `data-layer` + 공용 ConfigMap `data-layer-env` + Secret `data-layer-secrets` + CNPG 용 Secret `<clusterName>-app-user`(basic-auth) + ClusterRoleBinding
  `data-layer-default-admin` + Kafka 설정 ConfigMap 2종의 소유자.** 워크로드가 없고 이미지도 쓰지 않는다. 이 차트가 소유하는 값은 `graphLabelPrefix` 하나뿐이고 나머지는 전부 `global` 에서 온다.
  `_helpers.tpl` 이 `datalayer.kafkaBootstrap`·`postgresHost`·`postgresDsn`·`kafkaQuorumVoters` 를 조립한다(301-kafka·304 의 헬퍼와 같은 원본·같은 방식 — 복사본이 아니라 파생값).
  ⚠ **release 기록은 `-n default`** 에 둔다 — `data-layer` 는 이 차트가 만들 대상이라 설치 시점엔 없고, `--create-namespace` 를 쓰면 차트 안의 Namespace 오브젝트와 "already exists" 로 충돌한다.
  ⚠ `helm uninstall data-layer-base` 는 **네임스페이스째** 지운다(301~400 워크로드 전부). 값 변경은 `helm upgrade` 로만. 설정을 바꾸면 소비 워크로드를 사람이 재기동한다(다른 릴리스라 checksum 이 없다).
- `301-hadoop` — **HDFS HA 의 Helm 차트**: ZooKeeper ×3 · JournalNode ×3 · NameNode ×2(+ZKFC 사이드카) · DataNode ×3 = StatefulSet 4종이 `templates/hadoop-statefulset.yaml` 한 파일에 있다.
  **설계 원칙은 301-kafka 와 같다 — 장애는 쿠버네티스가 아니라 HDFS 자체 HA(ZKFC 자동 전환·QJM 쿼럼·블록 복제 3)로 막는다**: hostNetwork(Service 없음, 모든 주소가 노드 IP) + 정적 local PV(`hadoop-local`, 프로비저너 없음, Retain)
  11개가 `claimRef` 로 PVC `data-hadoop-<구성요소>-N` 에 미리 묶여 ordinal ↔ `global.hadoop.<구성요소>.nodeNames[N]` 이 고정된다(NameNode 는 ap·s1 둘뿐). `podManagementPolicy: Parallel`, **`updateStrategy: OnDelete`**(NameNode 는 Standby → Active 순으로 한 대씩).
  ConfigMap 이 없다 — core-site/hdfs-site/zoo.cfg 는 기동 스크립트가 values 로 생성한다(`hadoop.writeConf` define). 이미지 `hadoop`(Hadoop 3.4.3 + ZooKeeper 3.9.5 바이너리만, uid 1000)은 4종 공용.
  노드 디렉토리 `/data/hadoop-{zookeeper,journalnode,namenode,datanode}` 는 Ansible `hadoop_prereq` 가 root:root **2770** 으로 만들고(3노드 전부 — s2 의 namenode 디렉토리는 의도적으로 빈 채),
  차트의 `dfs.datanode.data.dir.perm=770` 과 **한 쌍**이다(한쪽만 바꾸면 DataNode 가 chmod 에 실패). `clusterId`(`CID-data-layer`)는 기존 데이터가 있으면 변경 금지. NameNode 초기화는 fsimage 유무로 판단한다(nn0 은 bootstrapStandby 실패 시 `-force` 없이 format, nn1 은 재시도 루프).
  소비자는 304-airflow 의 WebHDFS 원격 로그(`/airflow-logs` 를 user `airflow` 소유로 **미리** 만든다 — 없어도 기동은 되고 로그만 조용히 사라진다). `resources.requests` 는 노드 메모리 여유가 없어 주석 처리(BestEffort). ⚠ 300번대 중 **README·values.schema.json 이 아직 없는 유일한 차트** — 추가 대상.
- `301-kafka` — **Kafka 클러스터(StatefulSet `kafka`) + 운영 도구 3종(schema-registry · kafka-ui · kafka-exporter)**. **오퍼레이터를 쓰지 않는다** — Strimzi 는 `hostNetwork` 를 지원하지 않고(#3753·#7397 기각) 외부 접속이 NodePort 로 갈라져 STS 로 결정했다.
  **장애는 쿠버네티스가 아니라 Kafka 복제(RF 3)로 막는다** — hostNetwork(파드 IP = 노드 IP = 광고 주소, DNAT 없음) + 정적 local PV(`kafka-local`, 브로커당 data 10Gi + metadata 2Gi). **브로커 ID = 파드 ordinal = `global.kafka.brokers` 표 인덱스**이고 PV 의 `claimRef` 가
  PVC 이름(`data-kafka-N`)에 미리 묶여 kafka-N 은 brokers[N] 에만 뜬다. 노드가 죽으면 파드는 거기 남고 남은 복제본이 서비스를 잇는다 — 복구는 사람이 표를 고쳐 같은 ID 를 새 노드에서 띄운다(README '노드 장애'). **`updateStrategy: OnDelete`** — 사람이 한 대씩 지우며 URP 0 을 확인한다(README '롤링 재기동').
  서버 설정은 **300 의 ConfigMap `kafka-config`** 의 `server.properties.tpl` 이고 파드별 값(node.id·roles·광고 IP)은 기동 스크립트가 `POD_NAME`/`status.hostIP` 로 치환한다 — apache/kafka 이미지의 엔트리포인트는 쓰지 않는다(`kafka-storage format --ignore-formatted` 를 직접 돈다).
  앞 `controllers`(3)개가 controller+broker 겸용(정적 쿼럼), 그 뒤는 broker 전용 → 증설은 표 뒤에 붙이고 축소는 뒤에서 뺀다. 노드 디렉토리(`/data/kafka-broker`·`/data/kafka-controller`, root:root **2770**)는 Ansible `kafka_prereq` 가 만들고 `global.kafka.data/metadata.path` 와 글자 그대로 같아야 한다.
  **브로커에는 Service 를 두지 않는다**(headless·ClusterIP 둘 다 — STS `serviceName` 도 생략). 토픽 16종은 helm hook Job `kafka-topics`(`--if-not-exists` 멱등, 브로커 RF 개 등록 대기) — **`helm install/upgrade` 에 `--timeout 15m` 필수**(기본 5m 은 Job 예산 900s 보다 짧다).
  `min.insync.replicas=1` 은 구 로컬 설치 계약의 의도된 승계. ⚠ `helm uninstall` 은 PVC(volumeClaimTemplates)를 남기는데 **재설치 전에 PVC 를 먼저 지워야 한다**(pv-protection 이 PV 를 붙잡아 새 PV 에 안 붙는다 — Retain 이라 디스크 데이터는 그대로). `podManagementPolicy`·`serviceName` 은 불변 → `delete sts --cascade=orphan` 후 upgrade.
- `301-minio` — **내부 전용 S3(MinIO 단일 인스턴스)**: Deployment(`Recreate`) + RWO PVC(`longhorn` 20Gi) + ClusterIP 9000. 웹 콘솔은 `MINIO_BROWSER=off`(관리는 이미지 동봉 mc).
  **장애는 앱 복제가 아니라 Longhorn 스토리지 복제로 막는다** — 같은 301 번대의 kafka·hadoop 과 정확히 반대 전략(저쪽은 노드에 박힌 인프라, 이쪽은 노드를 옮겨 다니는 단일 인스턴스). nodeSelector 가 없고 노드가 죽으면 다른 노드에서 같은 볼륨을 붙는데,
  그 자동화는 100-base 의 `nodeDownPodDeletionPolicy` + values `tolerationSeconds`(60) + **옮겨 갈 노드에 Longhorn instance-manager 가 떠 있을 것**(2 vCPU 노드에서 CPU request 부족이면 조용히 안 뜬다) 셋이 맞물려야 한다 — 검증·판정·복구는 `RUNBOOK.md`.
  env 는 공용 `envFrom` 기본형을 쓰지 않는 문서화된 예외다(`MINIO_*` 접두 변수를 서버가 설정으로 해석). ⚠ 버킷(`config`·`warehouse`)과 설정 시드는 차트가 만들지 않는다 — `mc pipe` 로 한 번 부트스트랩(README '버킷', 2026-09-04 완료). `helm uninstall` 은 PVC 까지 지운다(longhorn reclaim Delete — 데이터 소실).
- `302-monitoring` — alloy(DaemonSet, hostNetwork, privileged) + prometheus + grafana. **수집/스크랩 설정의 소유자는 이 차트의 ConfigMap 3종**(`alloy-config`·`prometheus-config`·`grafana-datasource`)이고 파드 템플릿의 `checksum/*` 어노테이션이 렌더 결과 해시라
  `helm upgrade` 만으로 롤아웃된다. 그래서 alloy·prometheus 이미지는 `FROM` 한 줄(Harbor 경유 목적)이고 설정 변경에 재빌드·새 태그가 필요 없다. Grafana 대시보드 JSON 만 이미지에 굽는다(값 파생이 없는 순수 콘텐츠).
  prometheus·grafana 는 values `nodeNames`(s1/s2) 의 nodeAffinity 로 노드 후보를 정하고 PVC 는 `longhorn`. 스크랩 잡 6개(alloy-node·alloy-cadvisor·kafka-exporter·kafka-jmx·postgres·cnpg-operator)는 전부 kubernetes_sd(라벨·포트 이름) — static 타깃이 없다.
  300 이 먼저 설치돼 있어야 한다(네임스페이스·Grafana 계정 Secret·SD 용 API 권한 — 권한이 없으면 `/targets` 가 **조용히** 빈다). `helm uninstall` 은 PVC 두 개를 지운다.
- `303-postgres` — **플랫폼 PostgreSQL(CNPG Cluster `data-layer-postgres`, 인스턴스 2 — primary 1 + replica 1, nodeNames s1/s2 + required antiAffinity)**. 304 의 메타 DB 라서 앞 번호다.
  DB 3종(`data_layer`/`airflow`/`iceberg_catalog`)의 부트스트랩 정본이 여기다 — `bootstrap.initdb.postInitApplicationSQL`(timescaledb 확장·스키마·테이블·하이퍼테이블) + `Database` CR 2개. CNPG 는 `/docker-entrypoint-initdb.d/` 를 실행하지 않는다.
  앱 계정은 **superuser 가 아니다**(3개 DB 의 owner — 임시 관리는 `kubectl exec ... psql -U postgres`, 원격 superuser 로그인은 막혀 있다). 계정 Secret `<clusterName>-app-user` 는 300 소유(인증 정보의 소유자 — basic-auth 타입이라 공용 Opaque 와 분리).
  **`imageTag`(`16.15-v0.1.1`)는 `global.imageTag` 를 쓰지 않는 유일한 값** — CNPG 웹훅이 태그에서 PG 메이저를 읽어 `v0.1.0` 은 "invalid version tag" 로 거부된다(operand = PG 16.15 + timescaledb 2.29.0, `build_and_push.sh` 의 태그와 글자 그대로 같아야 한다).
  스토리지 `local-path` 40Gi(첫 install 후 변경 불가). 외부 접속은 `-external` LoadBalancer Service → MetalLB VIP `192.168.56.241:5432`(selector 가 `instanceRole: primary` 라 failover 를 따라간다). 메트릭 Service `-metrics` 를 302 가 긁는다.
  ⚠ 오퍼레이터가 클러스터별 SA/Role/RoleBinding 을 자동 생성하고 `enableServiceLinks: false` 를 넣을 수 없다 — '권한 모델'·파드 규약의 **문서화된 예외 2건**. ⚠ `helm uninstall` = Cluster CR 삭제 = PVC 까지 삭제(데이터 소실). 백업은 없다(`RUNBOOK.md` — `max_slot_wal_keep_size=-1` 이라 replica 방치 시 WAL 이 노드 디스크를 채운다).
- `304-airflow` — **Airflow 3.1.5, KubernetesExecutor**: apiserver/scheduler/dag-processor/triggerer(랩에서 `replicas: 0`) + 메타DB 초기화 Job. **코드(DAG·커스텀 패키지)는 이미지에 없다** — 노드 로컬 `/data/airflow-repo`(values `repo.hostPath`) 아래 디렉토리들(`repo.dirs`: dags·collector·processor·publisher·utils)을
  `airflowHome`(`/opt/airflow`) 아래 같은 이름에 하나씩 읽기 전용 hostPath 로 마운트한다(`/opt/airflow` 자체·`logs` 는 마운트하지 않는다). 반영은 **Ansible `airflow_repo_prereq` 의 `sync` 태그(3노드 rsync) → dag-processor 재스캔(30초)** 이라 `helm upgrade` 가 끼지 않고,
  재빌드 사유는 `requirements.txt` 변경뿐이라 **공용 `global.imageTag`** 를 쓴다. 노드 디렉토리(root:root **0755** — 컨테이너는 UID 50000 으로 읽기만)는 Terraform/Helm 밖 수동 단계다. ⚠ `hostPath.type: Directory` 라 경로가 없는 노드에서는 파드가 아예 뜨지 않는다('DAG 0개'로 조용히 도는 대신 거기서 멈추게 하려는 선택).
  **태스크 로그는 301-hadoop 의 WebHDFS**(`hdfs:///airflow-logs`, Connection `webhdfs_logs`, NameNode HTTP 두 주소 나열 — values `webhdfs.*`). Secret `airflow-env` 가 `AIRFLOW__*` 일체 + **DAG 이 읽는 Variable 4종/Connection 3종**(`AIRFLOW_VAR_*`/`AIRFLOW_CONN_*` — values `collector.*`·`secrets.*` + global 파생)을 만든다;
  `cdc_*` Connection 은 400 자격증명이라 UI 등록. 메타 DB 주소·DSN·Kafka bootstrap 은 `_helpers.tpl` 3개(`airflow.postgresHost`·`sqlAlchemyConn`·`kafkaBootstrap`)가 global 에서 파생한다. 태스크 파드 원형(ConfigMap `airflow-pod-template`)에도 같은 repo 마운트가 있어야 한다(태스크는 DAG 파일을 다시 파싱한다).
  ⚠ 초기화 Job 은 `post-install,post-upgrade` 훅이라 코어 4종 **뒤**에 돈다 — 신규 설치 때 코어가 잠시 CrashLoopBackOff 로 대기하는 것이 정상이고, 그래서 **`--wait`/`--atomic` 금지, `--timeout 10m` 필수**다. `helm uninstall` 은 안전한 편(PVC 없음)이나 hook Job `airflow-init` 은 남는다.
- `305-api` — data-layer-api Deployment(**replicas 1 고정** — `/quality/apply` 가 매퍼 파드를 delete 하므로 둘이 동시에 처리하면 같은 매퍼를 두 번 죽인다) + ClusterIP(`port` 8090) + Ingress(`global.hosts.api`, 업로드 상한 `proxyBodySize` 50m · 응답 대기 `proxyReadTimeout` 300).
  compose 의 docker socket 조작은 K8s API 어댑터로 대체했고 권한은 300 의 바인딩 하나. 파드가 Grafana 를 서버사이드로 부르는 경로가 있어 `global.ingressVip` 로 `hostAliases` 를 채운다(아래 '외부 노출').
- `306-cdc` — kafka-connect(Debezium) Deployment ×`replicas`(임시 2 — 원래 3, 노드 메모리) + ClusterIP `cdc-connect`(포트 `global.kafka.connectPort` — 300 의 `KAFKA_CONNECT_URL` 과 계약). 브로커 주소는 values 로 복사하지 않고 공용 ConfigMap 의 `KAFKA_BOOTSTRAP` 을
  `configMapKeyRef` 로 읽는다(해시 어노테이션 없음 — 브로커 표가 바뀌면 300 upgrade 후 `rollout restart`). 상태는 Kafka 내부 토픽 3종(`storageTopics` — 이름을 바꾸면 커넥터가 사라진 것처럼 보이거나 스냅샷을 다시 뜬다). 커넥터 등록은 차트 밖(관리 화면/REST). 첫 Ready 까지 플러그인 스캔 수 분(startupProbe 300s).
- `307-pipeline` — cdm-mapper 8종(values `mapper.modules` range — 라벨 `app=cdm-mapper` + `cdm.mapper/module` 은 305 DQ 적용과의 계약) + 컨슈머 3종(`consumer.kinds` — 이미지 + '코드가 읽는 이름 → 공용 키' env 번역표) + lineage 컨슈머 + tcp-socket-collector(hostNetwork + nodeSelector).
  전부 PVC·probe 없음(이상 감지 = 컨슈머 그룹 lag). 타임아웃 사슬: 300 의 `DATA_QUALITY_RESTART_DRAIN_TIMEOUT`(180) < `mapper.terminationGracePeriodSeconds`(200), 드레인 180 + 재기동 대기 60 = 240 < 305 `proxyReadTimeout`(300) — 하나를 올리면 나머지도 같이 올린다. ⚠ ingest 노드 라벨은 차트가 붙이지 않는다 — 수동 단계 `kubectl label node s2 ingest=true`(없으면 그 파드는 Pending).
- `400-test-rdb` — **CDC 소스 RDB 4종**(cdc-oracle · cdc-mssql · cdc-postgres · cdc-mysql) — StatefulSet(1) + ClusterIP + 초기화 ConfigMap(`files/*-initdb.*` 를 `tpl` 로 치환) + 자기 Secret `test-rdb-secrets`(values `secrets.cdcSourceDbPassword` — `data_pipeline/.env` 의 `CDC_SOURCE_DB_PASSWORD` 와 같아야 한다).
  번호가 400 인 것은 파이프라인(300번대)의 **입력을 흉내 내는 테스트 픽스처**라서다: 300번대는 이 스택 없이도 완결되고, 이 스택은 300번대의 어떤 오브젝트도 참조하지 않는다(공용 ConfigMap/Secret 도 쓰지 않는다). Service 이름·포트·계정/DB 이름이 Debezium 커넥터 JSON·Airflow `cdc_*` 커넥션과의 **대외 계약**이다.
  스키마·계정·CDC 활성화가 곧 커넥터의 전제조건이라 **초기화 스크립트가 이 스택의 본체**다 — 셋은 이미지 첫 기동 훅(빈 볼륨에서만 돈다 → 고치면 PVC `data-cdc-<db>-0` 삭제), mssql 만 helm hook Job(IF NOT EXISTS 라 멱등 — **`--timeout 20m`**). `storageClass: local-path`(저장소 규약의 명시적 예외 — 오라클만 약 12G 복제를 아낀다). ⚠ `helm uninstall` 은 PVC 를 남긴다.

**스택 간 의존성은 코드에 없다.** 순서는 디렉토리 번호 규칙이 담당하고, 그 사이에 Terraform/Helm 이 모델링 못 하는 수동 단계가 있다:
Ansible 선행작업(`longhorn_prereq`·`kafka_prereq`·`hadoop_prereq`·`airflow_repo_prereq`·`etc_hosts`) → 이미지 빌드/push(200 뒤, 300번대 전) → MinIO 버킷 시드(301-minio 뒤) → HDFS `/airflow-logs`(301-hadoop 뒤, 304 전) →
ingest 노드 라벨(307 전) → 커넥터 등록·`cdc_*` Airflow 커넥션(306/400 뒤). Helm 차트 사이의 값 전달은 오브젝트 **이름**(ConfigMap/Secret/Service)과 `values.common.yaml` 의 같은 원본으로 한다 — `terraform output` 은 Terraform 스택 사이에만 남았다.

## 명령어

```bash
# Terraform 스택 (100~200) — 스택마다 각자 init 부터, 루트에서는 -chdir
terraform -chdir=100-base init && terraform -chdir=100-base plan
terraform -chdir=100-base fmt -check                  # 포맷 검사
terraform -chdir=100-base validate                    # 문법 검증 (init 이후)

# Helm 차트 (300 이후) — 항상 -f values.common.yaml, 릴리스 네임스페이스는 data-layer (300 만 default)
helm lint 301-kafka -f values.common.yaml                                   # 문법 + values.schema.json
helm template kafka ./301-kafka -f values.common.yaml                       # 렌더 확인 (클러스터 접근 없음)
helm template kafka ./301-kafka -f values.common.yaml | kubectl diff -f -   # 라이브와 대조
helm template kafka ./301-kafka -f values.common.yaml | kubectl apply --dry-run=server -f -   # API 서버 검증
helm install data-layer-base ./300-data-layer-base -f values.common.yaml -n default          # 300 만 default
helm install kafka ./301-kafka -f values.common.yaml -n data-layer --timeout 15m             # hook Job 예산
helm upgrade monitoring ./302-monitoring -f values.common.yaml -n data-layer

# 이미지 빌드/push (200-harbor apply 뒤, 300번대 설치 전 — Terraform/Helm 밖 수동 단계)
/project/data_pipeline/scripts/build_and_push.sh <TAG>              # 23종 전부 → data-layer-harbor:80/data-layer/<name>:<TAG>
/project/data_pipeline/scripts/build_and_push.sh <TAG> <이름>...    # 선별 (예: v0.1.0 airflow hadoop)

# 노드 선행작업 (Ansible 저장소에서 — 2인자: <Ansible 절대경로> <all|태그>)
bin/start_kafka_prereq.sh / start_hadoop_prereq.sh / start_longhorn.sh <경로> all
bin/start_airflow_repo_prereq.sh <경로> all      # 디렉토리 + rsync      / sync → DAG 반영만
bin/start_configuration.sh <경로> etc_hosts      # 노드 /etc/hosts 재생성
```

| 차트 | 릴리스 이름 | 비고 |
|---|---|---|
| 300-data-layer-base | `data-layer-base` | `-n default`, `--create-namespace` 금지 |
| 301-hadoop / 301-kafka / 301-minio | `hadoop` / `kafka` / `minio` | kafka 는 `--timeout 15m` |
| 302-monitoring / 303-postgres | `monitoring` / `postgres` | 303 은 103 apply 이후 |
| 304-airflow | `airflow` | `--timeout 10m`, `--wait`/`--atomic` 금지 |
| 305-api / 306-cdc / 307-pipeline | `api` / `cdc` / `pipeline` | 307 은 ingest 라벨 먼저 |
| 400-test-rdb | `test-rdb` | `--timeout 20m` |

**`terraform apply`/`destroy` 와 `helm install`/`upgrade`/`uninstall` 은 사용자가 직접 실행한다.** Claude 는 파일 작성과
`plan`/`fmt`/`validate`/`helm lint`/`helm template`/`--dry-run=server` 수준 검증까지만 하고, 실행 명령어를 안내로 제공할 것.
이미지 태그(`global.imageTag`)를 올릴 때는 이름 인자 없이 전부 push 한다 — 한 차트만 선별 빌드하면 나머지 차트가 **없는 태그**를 가리켜 다음 upgrade 에서 ImagePullBackOff 가 된다(303 의 `imageTag` 는 별도 규칙).

## 규칙 (이 저장소의 비자명한 결정들)

### 공통

- **버전은 전부 정확 고정.** `>=`, `~>` 같은 범위 연산자 금지 — CLI(`required_version`), 프로바이더, 서드파티 Helm 차트 모두. 자체 차트 `Chart.yaml` 의 `version` 은 업그레이드 시 사람이 명시적으로 올린다(전부 0.1.0). 새 버전을 박기 전에 해당 레지스트리(registry.terraform.io, 차트 index.yaml)에서 실존 여부를 조회할 것.
- **리소스가 없는 프로바이더는 선언하지 않는다.** 100/101/103 은 helm 하나, 102 는 차트(helm) + MetalLB CR(kubernetes) 둘, 200 은 차트(helm) + Harbor API(harbor) 둘이다.
- **환경마다 달라야 하는 값은 default 를 주지 않는다** — Terraform 은 `variables.tf` 에 default 없이 `terraform.tfvars` 강제, Helm 은 `values.schema.json` 의 `required` 가 같은 역할(빠지면 렌더 전에 실패). 차트가 실제로 참조하는 `global` 키만 required 로 선언한다.
- 파일 분리: Terraform 은 `versions.tf` `providers.tf` `variables.tf` `terraform.tfvars` (`secrets.auto.tfvars`) + 컴포넌트별 tf — **`main.tf` 금지**(파일 이름이 곧 목차). Helm 은 `Chart.yaml` `values.yaml` `values.schema.json` `.helmignore` `templates/*.yaml` `templates/NOTES.txt` `README.md`(+ 운영 절차가 있으면 `RUNBOOK.md` — 301-minio·303).
- 주석은 한국어. "무엇"이 아니라 **"왜"** 를 적는다(무엇은 코드가 말한다). 한 주제는 2~4줄로, 반복 서술·compose 시절 회고·자명한 서술은 적지 않는다.
- **섹션 배너는 아래 형식 하나로 통일한다.** 기준 구현은 `200-harbor/variables.tf` · `200-harbor/harbor.tf`(tf) · `301-kafka/templates/kafka-statefulset.yaml`(yaml). `[섹션명]` 은 대괄호로 감싼 짧은 명사구, 설명이 없으면 그 줄만. 개별 리소스/필드에는 배너 대신 `# ...` 한두 줄 — 배너를 남발하면 목차 기능을 잃는다.

```hcl
# ===============================================
# [섹션명]
#
# 핵심 설명
# ===============================================
```

- **여러 줄 `<<-EOT` description 을 쓰지 않는다.** `description` 은 한 줄 사실 서술(그대로 `terraform output`/문서에 노출된다), 배경은 배너나 한 줄 주석으로.
- Terraform `helm_release` 의 values 는 인라인 `yamlencode()` — 한 화면을 넘으면 별도 파일로 분리.
- 최소주의: remote backend, atomic, modules, ArgoCD 등은 필요가 생기기 전까지 도입하지 않기로 결정됨.

### Helm 차트 규약

- **`global.*` 은 차트에 정의하지 않는다.** 정의처는 루트 `values.common.yaml` 하나이고, 차트 values.yaml 은 그 차트만 쓰는 값만 갖는다. 두 차트 이상이 같은 값을 보면(포트·노드 표·클러스터 이름) `global` 로 올린다 — 300 의 설정 ConfigMap 이 참조하는 값도 `global` 이어야 한다.
- **접속 주소는 값이 아니라 파생값이다.** 주소 문자열을 values 에 적어 두지 않고 원본(노드 표·clusterName·namespace·포트)에서 `_helpers.tpl` 이 조립한다 — 300·301-kafka·304 의 `kafkaBootstrap` 이 같은 원본을 같은 방식으로 조립하므로 어긋날 방법이 없다.
- **`_helpers.tpl` 은 값 '변환'이 끼는 조합만 둔다**(FQDN 파생, `urlquery` 가 들어가는 DSN, 표 → 목록). 단순 연결(레지스트리+태그 이미지 주소)·정적 블록(라벨·envFrom)은 각 템플릿에 직접 적는다 — 헬퍼로 감싸면 값 하나 보려고 파일을 왕복해야 하고 얻는 것이 없다. 정본은 304 README '차트 규약'.
- **설정 ConfigMap 과 그것을 읽는 파드가 같은 릴리스면 `checksum/<이름>: {{ include ... | sha256sum }}` 어노테이션을 파드 템플릿에 심어 `helm upgrade` 만으로 롤아웃한다**(302 전부, 304 `airflow-env`·pod-template, 301-kafka 도구 2종의 `checksum/kafka-bootstrap`). 다른 릴리스(300 의 `kafka-config`) 면 해시를 못 계산하므로 README 에 '사람이 재기동' 을 적는다.
- **Job 의 `spec.template` 불변은 `helm.sh/hook-delete-policy: before-hook-creation` 으로 푼다**(301 `kafka-topics`, 304 `airflow-init`, 400 `cdc-mssql-init`). hook Job 의 대기 예산은 반드시 **스크립트 루프 < `activeDeadlineSeconds` < helm `--timeout`** 순서로 닫고, install/upgrade 명령에 그 `--timeout` 을 적어 둔다(helm 기본 5m). 실패 로그를 남기려면 `backoffLimit: 0` + `restartPolicy: Never` 가 한 쌍이다.
  ⚠ hook 리소스는 release manifest 가 아니라 `helm uninstall` 이 지우지 않는다 — 완전 삭제 때 `kubectl delete job` 을 함께.
- **`helm uninstall` 의 결과는 차트마다 다르다 — README '주의' 를 먼저 읽는다.** 네임스페이스째 삭제(300) / PVC 삭제 = 데이터 소실(301-minio·302·303) / PVC 잔존 + 재설치 전 삭제 필요(301-kafka·301-hadoop — pv-protection) / PVC 잔존(400) / 안전(304·305·306·307).
- **StatefulSet 의 `serviceName`·`podManagementPolicy` 는 불변이다** → `kubectl delete sts <이름> --cascade=orphan` 으로 오브젝트만 지우고 `helm upgrade` 하면 같은 라벨의 파드를 그대로 입양한다(재기동 없음).
- **hostNetwork + 정적 local PV 패턴(301-kafka·301-hadoop)**: 자기 StorageClass(no-provisioner, WaitForFirstConsumer, Retain) + 노드마다 PV 를 range 로 찍고 `claimRef` 로 STS 의 PVC 이름(`<volume>-<sts>-<ordinal>`)에 미리 묶는다(ordinal ↔ 노드 고정). `podManagementPolicy: Parallel`(쿼럼 교착 방지) + `updateStrategy: OnDelete`(사람이 한 대씩) + `dnsPolicy: ClusterFirstWithHostNet` + `securityContext.fsGroup: 0` + `fsGroupChangePolicy: OnRootMismatch`. 노드 디렉토리는 Ansible 이 root:root **2770**(setgid) 으로 만든다 — `0770` 이면 kubelet 이 켠 setgid 가 재실행마다 벗겨져 다음 재기동 때 데이터 전체를 다시 chown 한다. PV 가 `Released` 로 남으면 `claimRef.uid` 만 patch 로 비운다(301-kafka README 'PV 재사용').
- **YAML 은 1.1 이다**(helm/kubectl) — 8진수는 `0755` 그대로(400 oracle `defaultMode`), 셸 변수 `${VAR}` 는 이스케이프 불필요(Go 템플릿은 `$` 를 건드리지 않는다). Terraform `yamldecode`(YAML 1.2) 규칙과 반대이니 옮겨 적을 때 주의.
- **`resources.requests` 는 당분간 주석 처리한 차트가 있다**(301-hadoop · 304 코어 4종+init · 305 · 306 · 307 · 400) — 노드(2 vCPU/약 3GB) 여유가 없어 그대로는 Pending 이라 스케줄러 검사를 뺀 임시 조치이고 대가는 BestEffort QoS(메모리 압박 시 먼저 evict). 301-kafka(1536Mi)·301-minio·302·303 은 requests 를 유지한다. 되살릴 때는 `kubectl describe node` 의 Allocated 를 먼저 본다. limits 는 어디에도 두지 않고 JVM 은 힙 고정으로 대신한다.
- 릴리스 네임스페이스: 300 만 `default`(네임스페이스가 아직 없어서), 나머지는 전부 `data-layer`(기록과 실체를 한곳에). `helm template` 은 CRD 를 검증하지 않으므로 CR 을 가진 차트(303)는 `--dry-run=server` 로 한 번 더 본다.

### 시크릿

- Terraform: 시크릿 변수는 `sensitive = true` + **`secrets.auto.tfvars`** 로 주입한다(현재 200-harbor 만). `terraform.tfvars` 는 값이 눈에 띄어야 하는 환경 설정용이라 시크릿을 넣지 않는다. 스택마다 `secrets.auto.tfvars.example` 을 둔다.
- Helm: 공유 자격증명은 `values.common.yaml` 의 `global.secrets`(300 이 Secret 두 개로 만든다), 한 차트만 쓰는 것은 그 차트 values 의 `secrets.*`(304 fernet/JWT/admin, 400 소스 DB 비밀번호). **개발 평문 규약**이고 운영 전환 시 SealedSecrets/SOPS 로 바꾼다. Secret 은 typed 오브젝트(`kind: Secret`, `stringData`)로만 만들고 `kubectl create secret` 수동 생성은 하지 않는다.
- ⚠ **이 저장소는 공개 전제이고(`github.com/sy0218/Infrastructure-as-Code-Terraform.kubernetes`), `*.tfstate` 와 `*.auto.tfvars` 를 일부러 gitignore 하지 않는다**(운영자 결정 — 랩 자격증명이라 노출돼도 실피해가 없다는 판단). **실계정을 쓰게 되는 순간 전제가 깨진다** — 그때는 `.gitignore` 에 네 줄을 되살리고 자격증명을 전량 교체해야 한다. `.terraform.lock.hcl` 은 항상 커밋, `.terraform/` 은 무시.

### kubernetes_manifest + templatefile (Terraform — 지금은 102-ingress 의 MetalLB CR 둘뿐)

- **템플릿 1파일 = YAML 문서 1개.** `yamldecode` 는 단일 문서만 받는다 — `---` 로 여러 문서를 넣으면 plan 이 죽는다.
- **8진수는 `0o755` 로 적는다.** `yamldecode` 는 YAML 1.2 라 `0755` 를 **십진수 755** 로 읽는다(kubectl/helm 은 1.1 이라 493). `defaultMode`·`fsGroup` 이 대상이고, 범위 제한이 없는 필드는 조용히 틀린 값이 들어간다(구 400 Terraform 판의 oracle 스크립트 실행 비트가 그 사례).
- **`--dry-run=server` 로 교차검증할 때 YAML 로 다시 덤프하지 말 것.** `ACCEPT_EULA: Y` 같은 값이 YAML 1.1 의 불리언으로 재해석되어 가짜 실패가 난다 — JSON 으로 뽑으면 타입이 보존된다.
- **셸 변수는 `$${VAR}` 로 이스케이프한다.** `.yaml.tftpl` 안의 `${...}` 는 Terraform 보간이라 빠뜨리면 `Invalid template interpolation value` 로 plan 이 실패한다.
- `for_each` 키는 안정적인 문자열. 리스트 인덱스 금지 — 순서가 바뀌면 전부 재생성된다.
- **API 서버가 기본값을 채우는 필드는 매니페스트에 명시한다**(프로브의 `timeoutSeconds`·`successThreshold` 등) — 생략하면 apply 가 `unexpected new value ... was null` 로 실패하고, 변경은 클러스터에 이미 반영된 뒤라 더 헷갈린다.
- **컨테이너를 추가할 때는 목록 맨 뒤에 붙인다.** 이 프로바이더는 `containers` 를 이름이 아니라 **위치로** 병합한다 — 앞에 끼우면 named port 가 사라져 `livenessProbe.httpGet.port: Invalid value: 0` 으로 죽는다.
- **Job 의 `spec.template` 은 불변** → `apply -replace=<리소스>`. Job 의 `controller-uid`/`job-name` 라벨은 `computed_fields` 에 `spec.template.metadata.labels` 를 넣어 '서버가 채우는 자리'라고 알린다(기본값 2개를 덮어쓰므로 같이 적을 것).
- 표준형: `manifest = yamldecode(templatefile("${path.module}/manifests/<파일>.yaml.tftpl", { ... }))`.

### 쿠버네티스 규약

- 모든 매니페스트에 `namespace: {{ .Values.global.namespace }}`, 공통 라벨 `app.kubernetes.io/part-of: data-layer`(+ `app`·`app.kubernetes.io/name`, 다중 구성요소 차트는 `app.kubernetes.io/component`). 선택 삭제가 필요한 PVC 에는 `app.kubernetes.io/name` 까지 붙인다(part-of 만으로는 kafka·hadoop PVC 가 같이 잡힌다).
- env 주입 기본형은 `envFrom: [configMapRef: data-layer-env, secretRef: data-layer-secrets]`, 워크로드 전용 값만 `env:` 로 덧붙인다(304 는 그 뒤에 `secretRef: airflow-env` — 순서상 겹치는 키는 Airflow 쪽이 이긴다). **예외**: `301-minio`(공용 `MINIO_*` 변수를 서버가 자기 설정으로 해석 → `secretKeyRef` 두 키), `400-test-rdb`(테스트 픽스처에 MinIO·Neo4j 자격증명이 들어가면 안 된다 → 자기 Secret 에서 `secretKeyRef`), 미들웨어(301-kafka 브로커·301-hadoop·302 alloy/prometheus — 앱 env 가 필요 없다).
- **모든 파드 spec 에 `enableServiceLinks: false`.** 자동 주입되는 도커 링크 시절 Service env 가 이름이 겹치면 컨테이너 설정을 조용히 덮어쓴다(`schema-registry` 가 `SCHEMA_REGISTRY_PORT` 로 실제로 죽었다). 유일한 예외는 303(CNPG 가 파드 템플릿을 소유 — 필드 없음).
- **`data-layer` 네임스페이스와 그 안의 오브젝트를 `kubectl` 로 직접 수정하지 말 것.** Helm 3-way merge 가 다음 `upgrade` 에서 되돌리거나 충돌시킨다. 값 변경은 values/템플릿 수정 → `helm upgrade`(추후 git push + argocd sync). 예외는 문서화된 수동 단계뿐(노드 라벨, MinIO 버킷, HDFS 디렉토리, 커넥터/Airflow 커넥션 등록, `--cascade=orphan` 재입양).
- 이미지는 예외 없이 Harbor 경유(`{{ .Values.global.harborRegistry }}/data-layer/<name>:{{ .Values.global.imageTag }}`), `imagePullPolicy: IfNotPresent`. 서드파티(prometheus·alloy·minio·test-rdb 4종)도 `FROM` 한 줄짜리 Dockerfile 로 `build_and_push.sh` 의 `IMAGES` 배열에서 함께 빌드해 Harbor 에 올린다 — 노드 containerd 가 Harbor 만 insecure 로 신뢰하기 때문. 태그는 불변으로 다루고 재사용하지 않는다(IfNotPresent 라 재사용하면 롤아웃이 조용히 아무 일도 안 한다). 예외는 303 의 `imageTag` 하나.
- nodeSelector 는 원칙적으로 금지(기본 스케줄러에 위임). 예외는 둘 — `tcp-socket-collector` 의 `ingest: "true"`(장비가 패킷을 보내는 노드), `200-harbor` 컴포넌트 7개(`harbor_node_name`). **노드 후보를 정하는 것은 values `nodeNames` + nodeAffinity** 로 한다(302 prometheus/grafana, 303 CNPG) — 리스트라 후보를 둘 이상 줄 수 있다. hostNetwork + local PV 워크로드는 PV 의 nodeAffinity 가 노드를 고정하므로 nodeSelector 가 필요 없다. 한 노드에 하나만 두는 것은 required podAntiAffinity(`kubernetes.io/hostname`)로, 흩기만 할 것은 preferred 로(306 — required 면 노드 1대 장애 시 영구 Pending).
- hostNetwork 파드(301-kafka·301-hadoop·302 alloy·307 tcp-socket)는 `dnsPolicy: ClusterFirstWithHostNet` 을 함께 둔다 — 없으면 파드 안에서 Service 이름이 안 풀린다. 그 포트는 노드 전체에서 유일해야 한다(`ss -lnt` 로 설치 전 확인).
- Deployment 가 RWO PVC 를 쓰면 `strategy: Recreate`(301-minio·302 — RollingUpdate 는 Multi-Attach 로 죽는다).

### 외부 노출 (Ingress 기본 · 비-HTTP 는 VIP 또는 hostNetwork — 예외는 아래 목록뿐)

- **브라우저가 접속하는 HTTP 서비스는 Ingress 로 노출한다.** 진입점은 MetalLB VIP 하나(`102-ingress`, .240)이고 접속 주소 형식은 `http://<호스트명>` — **포트가 붙지 않는다**. 갈래는 인그레스가 Host 헤더로 나누므로 서비스가 늘어도 열리는 포트는 그대로다.
- **비-HTTP 노출은 인그레스 대상이 아니다:**
  - `303-postgres` — **전용 MetalLB VIP**(.241:5432, 풀은 102 소유). DB 프로토콜은 Host 헤더가 없어 L7 을 못 타고, NodePort 는 30000-32767 제약 때문에 표준 포트를 못 지킨다 — VIP 는 지킨다.
  - `301-kafka` — **hostNetwork**(노드 IP:9092/9093/9094, JMX 9404). 클라이언트는 bootstrap 뒤 브로커가 광고한 주소로 다시 붙으므로 브로커마다 주소가 필요하다 — VIP 는 4개가 들고 홉이 늘며 NodePort 는 DNAT 가 낀다. 노드에 박힌 인프라라 노드 IP 를 그대로 광고하는 것이 가장 짧은 경로이고 클러스터 안팎이 같은 주소를 쓴다.
  - `301-hadoop` — **hostNetwork**(NameNode 8020/9870, JournalNode 8485/8480, ZKFC 8019, DataNode 9866/9867/9864, ZooKeeper 2181/2888/3888/7000). HDFS 클라이언트도 NameNode 가 알려 준 DataNode 주소로 직접 붙는다(Kafka 와 같은 이유). WebHDFS/Web UI 는 노드 IP:9870.
  - `tcp-socket-collector`(hostNetwork, 리슨 포트가 런타임 DB 값), `alloy`(hostNetwork DaemonSet).
- **`400-test-rdb` 의 소스 RDB 4종은 ClusterIP 뿐이다 — NodePort 를 추가하지 않는다.** 소비자(kafka-connect·airflow)가 전부 클러스터 안이라 Service DNS 로 충분하고, 사람은 `kubectl port-forward svc/cdc-postgres 15432:5432` 처럼 docker 시절 포트를 재현한다(NOTES).
- **`200-harbor` 의 host 는 접속 주소가 아니라 이미지 이름의 첫 마디다.** 이미지 참조는 `data-layer-harbor:80/data-layer/<name>:<tag>` — **`:80` 은 생략 불가**(Docker 이미지 참조 파서는 첫 마디에 `.`/`:` 이 없으면 레지스트리가 아니라 docker.io 네임스페이스로 정규화해 push/pull 이 Docker Hub 로 간다). 노드 containerd 는 그 문자열과 **글자 그대로 같은** `certs.d/<이름>/hosts.toml` 을 찾는다. 이름을 바꾸려면 아래 '같은 커밋' 표의 harbor 줄 전부가 함께 간다.
- **레지스트리 Ingress 에는 어노테이션 넷이 필수다** — `proxy-body-size: "0"`, `proxy-request-buffering: "off"`, `proxy-read/send-timeout` 상향(600), `ssl-redirect: "false"`(차트 기본값이 `"true"`). 빠뜨리면 UI 는 멀쩡한데 `docker push` 만 죽는다.
- **인그레스 뒤에서는 IP 로 우회 pull 이 불가능하다**(Host 헤더가 IP 라 어떤 규칙에도 안 걸려 404). 이름 해석이 의심되면 `/etc/hosts` 와 VIP 의 ARP 응답을 먼저 본다.
- **Ingress 오브젝트는 각 앱 차트가 소유한다.** `ingressClassName: {{ .Values.global.ingressClassName }}`(nginx) 를 반드시 명시 — 차트가 이 클래스를 기본값으로 만들지 않아 빠뜨리면 조용히 404 다. 예외: 200-harbor 는 Ingress 도 차트가 만든다(`expose.ingress.className`).
- **경로 기반이 아니라 호스트 기반으로 가른다.** 호스트 기반은 앱이 자기가 루트에 있다고 믿어도 그대로 동작한다(경로 기반이면 Grafana 등 앱마다 base path 설정이 필요).
- **호스트명은 서비스마다 다르다 — `data-layer-<서비스>`.** 정본은 `values.common.yaml` 의 **`global.hosts`**(kafkaUi·airflow·api·grafana·prometheus)와 200 의 `harbor_host` 이고, 300 은 같은 값으로 `KAFKA_UI_URL`·`AIRFLOW_UI_URL`·`GRAFANA_URL`·`GF_SERVER_ROOT_URL` 을 조립한다. 추가/변경하면 Ansible `data_layer_vip_dns_names`(노드 `/etc/hosts`)와 같은 커밋에서 고친다(그 목록의 `data-layer-headlamp` 는 이 저장소에 스택이 없다). 공유 이름 `external_dns_name` 은 폐기됐다 — 되살리지 말 것.
- **호스트명에 밑줄·`.local` 을 쓰지 않는다.** DNS 라벨은 영문/숫자/하이픈만(RFC 1123 — 레지스트리는 밑줄이 있으면 이미지 참조로 파싱조차 안 된다), `.local` 은 mDNS 예약 도메인(RFC 6762)이라 systemd-resolved 가 가로챈다.
- **`<앱>_nodeport` 류 값을 다시 만들지 말 것** — 인그레스나 전용 VIP 로 노출한 서비스에 NodePort 를 되살리면 접속 경로가 둘로 갈라진다.
- **`externalTrafficPolicy` 는 인그레스 컨트롤러 Service 에만 `Local`.** ① 클라이언트 IP 보존 ② MetalLB L2 는 `Local` 일 때 준비된 엔드포인트가 있는 노드에서만 VIP 를 광고. 앱 Service 는 전부 ClusterIP 라 이 필드가 무의미하다.
- **인그레스 컨트롤러는 `replicaCount` 2 + required podAntiAffinity 로 노드에 흩는다.** 1 이면 전 서비스의 SPOF, 같은 노드에 뭉치면 복제 목적이 사라진다.
- HA 는 "VIP 는 MetalLB 가 살아 있는 노드로 옮긴다" + "이름 전부가 그 VIP 하나를 가리킨다" 조합이다. 노드 `/etc/hosts` 는 Ansible `etc_hosts` 롤이 **노드 IP 계열(`data-layer-neo4j` — 노드당 1줄, 전환 주체는 클라이언트) + VIP 계열(harbor·kafka-ui·airflow·api·grafana·prometheus·headlamp — 1줄, 전환 주체는 MetalLB)** 로 만든다. 한 이름을 두 계열에 동시에 넣지 말 것.
- **ClusterIP 이름/포트는 그대로 둔다.** grafana→prometheus, airflow scheduler→apiserver(`AIRFLOW__CORE__EXECUTION_API_SERVER_URL`), api→매퍼 같은 내부 호출은 Service DNS + 원래 포트를 쓴다 — 외부 이름으로 바꾸면 파드→VIP→인그레스→파드로 우회해 인그레스 장애가 곧 태스크 정지가 된다.
- **`data-layer-*` 호스트명은 클러스터 '밖' 이름이다 — 파드는 풀지 못한다**(CoreDNS 는 노드 `/etc/hosts` 를 보지 않는다). 파드가 이 이름으로 나가야 하는 예외는 **`hostAliases` 로 VIP 1줄**(`global.ingressVip`) — 현재 유일한 사례는 `305-api` → Grafana 대시보드 목록(브라우저가 직접 부르면 CORS).
- **업로드 경로가 있는 Ingress 에는 `proxy-body-size`(기본 1m → 413), 오래 걸리는 동기 엔드포인트에는 `proxy-read-timeout`(기본 60초 → 504)을 붙인다.** 현재 대상은 `305-api`(DQ 규칙·도메인 설정 업로드 / DQ '적용' 최대 240초) — 값은 values `ingress.*`, 근거는 307 `terminationGracePeriodSeconds` 와의 사슬.

### 권한 모델 — 워크로드별 RBAC 을 두지 않는다

1인 운영 환경이라 권한 분리를 하지 않기로 했다. 권한 오브젝트는 **`300-data-layer-base/templates/clusterrolebinding.yaml` 의 ClusterRoleBinding `data-layer-default-admin` 하나뿐**이며, `data-layer` 네임스페이스의 `default` ServiceAccount 에 `cluster-admin` 을 준다.

- 워크로드에 **`serviceAccountName` 을 쓰지 않는다**(default SA 자동 적용). ServiceAccount / Role / RoleBinding / ClusterRole 을 새로 만들지 말 것. 예외는 303 — CNPG 오퍼레이터가 클러스터별 SA/Role/RoleBinding 을 스스로 만든다(우리 소유가 아니고, 지우면 인스턴스가 API 서버를 못 불러 멈춘다).
- **"RBAC 을 껐다"가 아니다.** kube-apiserver 가 `--authorization-mode=Node,RBAC` 으로 뜨므로 바인딩이 없으면 파드의 API 호출은 전부 403 이다 — 305 의 DQ '적용'(매퍼 재기동)·수집기 상태 조회, 304 scheduler 의 태스크 파드 생성이 실패하고, prometheus 는 `/targets` 가 **조용히** 빈다.
- 대가: 이 네임스페이스의 모든 파드가 클러스터 관리자 권한을 갖는다. 신뢰 경계가 생기면 이 파일을 지우고 워크로드별 Role 로 되돌리는 것이 정공법이다.

### 같은 커밋에서 함께 바꿔야 하는 값 (저장소 밖과의 커플링)

| 이 저장소 | 함께 가는 곳 |
|---|---|
| `global.nodes[].ip` · `global.kafka.brokers[].ip` · 304 `webhdfs.hosts` · `global.neo4jBoltUri` | Ansible `host.yml` 의 `ansible_host` |
| `global.harborRegistry`(`data-layer-harbor:80`) · 200 `harbor_host`/`externalURL`/harbor 프로바이더 URL | Ansible `containerd_insecure_registries`·`buildkit_registry`, `build_and_push.sh` 의 `REGISTRY` |
| 200 `harbor_admin_password`(secrets.auto.tfvars) | Ansible `buildkit_registry_password` |
| 102 `ingress_vip` · `global.ingressVip` | Ansible `ingress_vip` |
| 102 `postgres_vip` · 303 `externalIp` | — (둘이 같아야 한다) |
| `global.hosts.*` · 200 `harbor_host` | Ansible `data_layer_vip_dns_names`, 접속 PC 의 hosts |
| `global.kafka.data/metadata.path` | Ansible `group_vars/kafka.yml` |
| 301-hadoop `hadoop.<구성요소>.path` · `dfs.datanode.data.dir.perm=770` | Ansible `group_vars/hadoop.yml`(경로·`hadoop_data_mode: '2770'`) |
| 304 `repo.hostPath` | Ansible `group_vars/airflow.yml` 의 `airflow_repo_dir` |
| `global.imageTag` · 303 `imageTag` | `build_and_push.sh <TAG>` 의 태그(303 은 `16.15-<TAG>` 형식) |
| `global.secrets.collectorCryptoKey` · 400 `secrets.cdcSourceDbPassword` | `data_pipeline/.env`·`airflow.env`(값 원천 문서) |
| 301-kafka `topics` · 307 `mapper.modules` · 400 Service 이름/포트/계정 | `data_pipeline` 의 kafka.conf TOPICS · 매퍼 모듈 파일 · Debezium 커넥터 JSON |

## 커밋 컨벤션 ([COMMIT_CONVENTION.md](COMMIT_CONVENTION.md))

- `type(scope): subject` — 제목은 한국어, 50자 이내, 마침표 없음, 명령형("추가" ⭕ / "추가함" ❌). 한 커밋에는 한 가지 변경만. type: feat / fix / docs / refactor / style / test / chore / ci, scope 는 스택 번호(`301-kafka`, `102-ingress`) 위주.
- 원격은 GitHub(`sy0218/Infrastructure-as-Code-Terraform.kubernetes`, main). tfstate 가 커밋 대상이므로 Terraform apply 뒤에는 state 변경분도 같은 흐름에서 커밋한다(`chore: ... state 최신화`).

## 알려진 문서 잔재 (코드가 정본이다)

- 루트 README '운영 노트' 의 **"DAG는 airflow 이미지에 굽는다"** 절은 구 설계다 — 현재 304 는 노드 hostPath + rsync(위 304 항목). 같은 README 의 '변경 관리 규칙'(`variables.tf` 의 `<앱>_host`, 300 `<앱>Host`, `305-api/terraform.tfvars`)·스토리지 표의 "Harbor = longhorn"(실제 local-path)·`secrets.auto.tfvars`(Git 제외) 서술도 Terraform 시절 것이다.
- 300 README '추후 ArgoCD' 가 가리키는 `/my_project/test/README.md` 는 존재하지 않는다(`/project/test/` 에도 없다).
- 304 README 의 `/my_project/...` 경로는 이 랩에서 `/project/...` 다.
