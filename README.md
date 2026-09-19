# ☸️ `Terraform` + `Helm` 기반 `Kubernetes` 배포 자동화 (`IaC`)

**`Kubernetes` 리소스를 코드로 선언하고,
`Data Pipeline Stack` 을 자동으로 배포/관리하기 위한 `IaC` 프로젝트 입니다.**

`Infrastructure as Code(IaC)` 기반으로 **클러스터 위의 애플리케이션을 코드로 관리하여 동일한 환경을 언제든 재현**할 수 있으며, **기능별로 구성 요소를 분리해 필요한 부분만 독립적으로 배포하고 관리할 수 있도록 표준화된 배포 체계를 제공**합니다.

플랫폼과 애플리케이션의 **변경 주기와 관리 목적이 다르기 때문에 도구를 분리**합니다.
- **Terraform → 플랫폼 기본 구성**  
- **Helm → 쿠버네티스 애플리케이션 배포**
- **ArgoCD → GitOps 기반 애플리케이션 지속 배포/상태 동기화**

---
</br>

## ✨ 도구를 나누는 기준

| 구간 | 대상 | 도구 | 목적 |
|---|---|---|---|
| `100 ~ 200` | `Storage` / `LoadBalancer` / `Ingress` / 커스텀 `Operator` / `Harbor` | **`Terraform`** | 플랫폼 기반을 구성하고 버전/설정을 고정 |
| `300 이후` | `Data Pipeline` 애플리케이션 | **`Helm`** | 애플리케이션을 패키징하고 지속적으로 배포/업데이트 |

---

### 왜 이렇게 나누는가?

`Storage`, `LoadBalancer`, `Ingress`, `Registry` 같은 기반 구성은 애플리케이션보다 변경 빈도가 낮기 때문에 `Terraform`으로 **버전과 설정을 코드로 고정하고 `plan → apply` 방식으로 관리**합니다.

반면 **애플리케이션은 운영 과정에서 변경이 계속 발생합니다.**
기능 수정, 이미지 업데이트, 설정 변경, 스케일 조정, 버전 업그레이드, 롤백 및 재배포 등이 반복되기 때문에 애플리케이션을 **`Helm Chart`로 패키징**하여 변경에 유연하게 대응할 수 있도록 구성합니다.

향후 `ArgoCD`를 적용하면 `Git`에 반영된 `Helm` 변경 사항을 `Kubernetes` 클러스터에 자동으로 동기화하여 **GitOps 방식의 지속적인 배포 체계**로 확장할 수 있습니다.

---
</br>

# ✨ 주요 특징
- **역할별 도구 분리**
  - 플랫폼(100~200)은 Terraform
  - 애플리케이션 워크로드(300 이후)는 Helm 차트(+ ArgoCD)
- **스택 기반 모듈 구조** 
  - 번호 디렉토리 하나 = 독립 스택(Terraform 루트 모듈 또는 Helm 차트)
  - 번호가 → 적용 순서 입니다.

---
</br>


# 📋 프로젝트 환경
| 항목 | 내용 |
|------|------|
| OS | Ubuntu 24.04 |
| Ansible | OS 기본 설정 / K8s 클러스터 / 노드 선행작업 |
| Kubernetes | kubeadm 3노드 (ap=control-plane / s1=worker-node / s2=worker-node), `v1.34.4` (패키지 핀 `1.34.4-1.1`, hold) |
| Container Runtime | containerd `2.2.1-0ubuntu1~24.04.3` + runc `1.3.4-0ubuntu1~24.04.1` → 버전 hold (AppArmor DENIED 버그 수정 포함), sandbox `pause:3.10.1` |
| CNI | Cilium `1.20.1` → eBPF Native Routing + kube-proxy replacement + Hubble UI |
| Terraform | `1.15.8` → 플랫폼(100~200) 기본 구성 프로비저닝 |
| Helm | `3.19.0` → 데이터 레이어 워크로드 배포 |
| Provider | kubernetes `2.38.0` / helm `3.2.0` / harbor `3.10.21` |
| BuildKit | `0.32.2` → docker 없이 이미지 빌드/push, Harbor 연동 |


---
</br>

# 📂 디렉토리 구조
```bash
Infrastructure-as-Code-Terraform.kubernetes/
│
│ # ── 플랫폼 인프라 (Terraform) ────────────────────────────────
├── 100-base/               # Kubernetes 기본 스토리지 구성 (StorageClass, Longhorn)
├── 101-metallb/            # 온프렘 LoadBalancer 구성 (MetalLB)
├── 102-ingress/            # 외부 트래픽 진입점 구성 (VIP, ingress-nginx, PostgreSQL VIP)
├── 103-cnpg/               # PostgreSQL 운영을 위한 CloudNativePG Operator
├── 200-harbor/             # 사설 컨테이너 이미지 레지스트리 (Harbor)
│
│ # ── 애플리케이션 플랫폼 (Helm + ArgoCD 예정) ─────────────────
├── 300-data-layer-base/    # 데이터 레이어 공통 리소스 (Namespace, ConfigMap, Secret, RBAC)
├── 301-hadoop/             # HDFS HA (ZooKeeper, JournalNode, NameNode+ZKFC, DataNode)
├── 301-kafka/              # Kafka(KRaft) 클러스터 및 운영 도구 (Schema Registry, UI, Exporter)
├── 301-minio/              # 내부 전용 S3 (MinIO 단일 인스턴스 + Longhorn PVC)
├── 302-monitoring/         # 모니터링 스택 (Alloy, Prometheus, Grafana)
├── 303-postgres/           # PostgreSQL 클러스터 구성 (CNPG, 2인스턴스)
├── 304-airflow/            # 워크플로우 오케스트레이션 (Airflow)
├── 305-api/                # 데이터 레이어 API 및 관리 서비스 (FastAPI)
├── 306-cdc/                # CDC 파이프라인 (Kafka Connect, Debezium)
├── 307-pipeline/           # 데이터 처리 및 Consumer 파이프라인
└── 400-test-rdb/           # CDC 연동 테스트용 RDB (Oracle, SQL Server, PostgreSQL, MySQL)
```

---
</br>

## 🏗️ Terraform 스택의 공통 파일 구성 (100 ~ 200 스택)

```bash
각 스택 내부(공통 파일 구성):
├── versions.tf             # Terraform 및 Provider 버전 고정
├── providers.tf            # Kubernetes Provider 설정
├── variables.tf            # 변수 정의 (설명 / 타입)
├── terraform.tfvars        # variables.tf 에서 정의한 변수 설정값 명시
├── secrets.auto.tfvars     # 비밀번호 등 민감 정보 (Git 제외)
└── <컴포넌트>.tf           # 컴포넌트별 Terraform 리소스

```
> **번호 디렉토리 하나가 독립된 `Terraform` 루트 모듈이며 각자 자기 `state`를 가집니다.**

> **설계 원칙**
>
> - **1개의 번호 디렉토리 = 1개의 독립적인 Terraform 프로젝트**
> - **1개의 `.tf` 파일 = 1개의 기능(컴포넌트)**
> - 스택 간 의존성은 **배포 순서(디렉토리 번호)** 로 관리합니다.

---
</br>

## ⎈ Helm 차트 스택의 공통 파일 구성 (300 이후)

```bash
각 차트 내부(공통 파일 구성):
├── Chart.yaml              # 차트 이름/버전 (정확 고정)
├── values.yaml             # 환경별 설정값
├── values.schema.json      # 필수 키/형식 검증 (누락/오타를 배포 전에 차단)
├── templates/*.yaml        # Kubernetes YAML 템플릿
└── templates/NOTES.txt     # 설치 후 안내 출력
```

---
</br>

# ⚙️ 0단계 → 이미지 빌드/푸시 (Terraform/Helm 밖 수동 단계)
> **`200-harbor` apply 직후, 워크로드 스택(`301~307`, `400`) 배포 전에 한 번 실행합니다.**
```bash
docker login data-layer-harbor:80           # 사전: /etc/docker/daemon.json 의 insecure-registries ["data-layer-harbor:80"] (docker 경로 — buildctl 경로는 Ansible buildkitd 롤이 인증 파일을 만든다)
/project/data_pipeline/scripts/build_and_push.sh v0.1.0
```
- 모든 워크로드는 `data-layer-harbor:80/data-layer/<name>:<tag>` 를 pull 한다
- 여기서 쓴 태그를 `values.common.yaml` 의 `global.imageTag` 에 **그대로** 넣는다
  (예외: `303-postgres/values.yaml` 의 `imageTag` 는 `16.15-<tag>` 형식 → CNPG 가 태그에서 PG 버전을 읽는다. `build_and_push.sh 16.15-<tag> postgres` 로 따로 push)
- `[주의]` `imagePullPolicy: IfNotPresent` 라서 **태그 재사용 금지**

---
</br>

# 🚀 배포 실행
**번호 순서대로** 배포합니다. 
- 플랫폼(`100~200`)은 → `Terraform`
- 데이터 레이어 워크로드(`300 이후`)는 → `Helm`

```bash
# Terraform 스택
terraform -chdir=<스택> fmt -check     # 포맷 검사
terraform -chdir=<스택> validate       # 문법 검증 (init 이후)


# Helm 차트 스택
helm lint <차트 디렉토리>                                    # 문법 + values.schema.json 

[검증]
helm template <릴리스> <차트 디렉토리> | kubectl diff -f -   # 배포 전 변경 미리보기
```

---
</br>

## 1️⃣ 플랫폼 → Terraform (100 ~ 200)

```bash
# 테라폼/Helm 프로젝트 디렉토리 이동
cd /project/Infrastructure-as-Code-Terraform.kubernetes
```

---

### 🔹1. 100-base
- **Kubernetes 스토리지 `PV` 구성 (`StorageClass, Longhorn`) 프로비저닝**

```bash
1. 100-base 실행
terraform -chdir=100-base init    → Terraform 실행 환경 준비 / Provider 다운로드
terraform -chdir=100-base plan    → 무엇을 변경할지 미리 확인
terraform -chdir=100-base apply   → Kubernetes 스토리지 PV 구성 (StorageClass, Longhorn)

[검증]
1. 쿠버네티스 스토리지 클래스 확인
kubectl get sc → local-path = defaut / longhorn

2. 파드 기동 상태 확인
kubectl get pods -n local-path-storage → 파드 Running 확인
kubectl get pods -n longhorn-system → 파드 Running 확인

3. Longhorn이 노드 3대를 인식했는지
kubectl get nodes.longhorn.io -n longhorn-system → READY 컬럼 = True
```

---

### 🔹2. 101-metallb
- **온프레미스 `LoadBalancer` 구현체(`MetalLB`) 프로비저닝**
  - 온프레미스 환경에서 `type: LoadBalancer Service`가 `<pending>` 상태에 머무르는 문제를 해결하기 위해 `VIP` 할당 및 `L2(ARP)` 광고 기능을 제공
  - **이 스택은 `MetalLB`의 `Controller`와 `Speaker`만 설치하며**, VIP 대역(IPAddressPool)과 광고 정책(L2Advertisement)은 102-ingress 스택에서 관리

```bash
1. 101-metallb 실행
terraform -chdir=101-metallb init    → Terraform 실행 환경 준비 / Provider 다운로드
terraform -chdir=101-metallb plan    → 무엇을 변경할지 미리 확인
terraform -chdir=101-metallb apply   → MetalLB 구현체 구성

[검증]
# 1. MetalLB Pod가 정상적으로 실행 중인지 확인
kubectl get pods -n metallb-system

# 2. MetalLB가 사용하는 CRD가 Kubernetes에 등록되었는지 확인
kubectl get crd | grep metallb

# 3. BGP 관련 frr-k8s가 실행되지 않는지 확인
kubectl get ds -n metallb-system
```

---

### 🔹3. 102-ingress

- **클러스터 외부 진입점(VIP) 구성**
  - MetalLB `IPAddressPool` + `L2Advertisement`로 VIP 2개 할당
  - `ingress-vip` → `ingress-nginx`를 통한 **HTTP(L7) 단일 진입점**
  - `postgres-vip` → `303-postgres-external` Service를 통한 **PostgreSQL TCP(L4) 전용 진입점**

- **ingress-nginx HA 구성**
  - `replicaCount: 2` + `podAntiAffinity`로 노드 분산
  - `externalTrafficPolicy: Local`로 **클라이언트 원본 IP 보존**
  - MetalLB는 `ingress-nginx` Pod가 실행 중인 노드에서만 VIP 광고

- **Ingress 리소스 관리**
  - 이 스택에서는 **Ingress Controller만 설치**
  - 실제 `Ingress` 리소스는 **각 애플리케이션 스택에서 관리**

```bash
1. 102-ingress 실행
terraform -chdir=102-ingress init    → Terraform 실행 환경 준비 / Provider(helm, kubernetes) 다운로드
terraform -chdir=102-ingress plan    → 무엇을 변경할지 미리 확인
terraform -chdir=102-ingress apply   → VIP 등록 + ingress-nginx 구성

[검증]
# 1. VIP 풀/광고 정책이 등록되었는지 확인 (ingress-vip, postgres-vip)
kubectl get ipaddresspool,l2advertisement -n metallb-system

# 2. ingress-nginx Service가 VIP를 받았는지 확인 (EXTERNAL-IP = ingress_vip, <pending> 아님)
kubectl get svc -n ingress-nginx ingress-nginx-controller

# 3. 컨트롤러 파드 2개가 서로 다른 노드에 떠 있는지 확인
kubectl get pods -n ingress-nginx -o wide

# 4. VIP를 광고 중인 노드가 컨트롤러 파드가 있는 노드인지 확인 (externalTrafficPolicy: Local)
kubectl describe svc -n ingress-nginx ingress-nginx-controller | grep nodeAssigned

# 5. 외부에서 VIP로 실제 응답 확인 → 404 Not Found면 정상 (Ingress 규칙이 아직 없을 뿐, nginx까지 도달)
curl -i http://<ingress_vip>/
```

---

### 🔹4. 103-cnpg

- **CloudNativePG(CNPG) Operator + CRD 설치**
  - Kubernetes에서 PostgreSQL의 **초기화/복제/Failover**를 자동 관리
  - `Cluster`, `Database`, `Pooler` 등의 **CNPG CRD 등록**

- **PostgreSQL 클러스터는 이 스택에서 생성하지 않음**
  - `103-cnpg` → Operator + CRD 설치
  - `303-postgres` → `Cluster` CR 생성 → PostgreSQL 클러스터 운영
  - 따라서 **103-cnpg가 먼저 설치되어야 303-postgres의 `Cluster` CR 생성 가능**

- **Operator 이미지는 차트 기본 이미지(`ghcr.io`) 사용**
  - 폐쇄망 환경에서는 외부 Registry 접근이 불가하므로
    **노드 3대에 이미지 사전 Pull 필요**
  - `crictl pull`로 이미지 선반입

```bash
1. 103-cnpg 실행
terraform -chdir=103-cnpg init    → Terraform 실행 환경 준비 / Provider 다운로드
terraform -chdir=103-cnpg plan    → 무엇을 변경할지 미리 확인
terraform -chdir=103-cnpg apply   → CNPG 오퍼레이터 + CRD 구성

[검증]
# 1. CNPG 오퍼레이터 Pod가 정상적으로 실행 중인지 확인
kubectl get pods -n cnpg-system

# 2. CNPG CRD(Cluster, Database, Pooler 등)가 Kubernetes에 등록되었는지 확인
kubectl get crd | grep cnpg.io
```

---

### 🔹5. 200-harbor
- **컨테이너 이미지 레지스트리(`Harbor`) 프로비저닝**
  - 전 스택의 이미지 저장소로 사용하며, HTTP 레지스트리이므로 각 노드의 `containerd`에 `insecure-registry` 설정이 필요하다.
  - Harbor의 `Service`와 `Ingress`를 함께 생성하고, 대용량 이미지 `Push`를 위해 Ingress의 업로드 용량/버퍼링/타임아웃/HTTPS 리다이렉트를 설정한다.
  - Harbor 컴포넌트 7종과 PVC 5종을 `harbor_node_name`에 고정 배치한다.
  - `local-path PV`가 노드에 종속되므로 배치 노드 변경 시 재설치가 필요하다.

```bash
1. 200-harbor 실행
terraform -chdir=200-harbor init    → Terraform 실행 환경 준비 / Provider 다운로드 (helm · harbor)
terraform -chdir=200-harbor plan    → 무엇을 변경할지 미리 확인
terraform -chdir=200-harbor apply   → Harbor 설치 + data-layer 프로젝트 생성

[검증]
# 1. 컴포넌트 7종이 모두 Running 이며 지정한 단일 노드에 배치되었는지 확인
kubectl get pods -n harbor -o wide

# 2. PVC 5종이 모두 Bound 이며 StorageClass 가 local-path 인지 확인
kubectl get pvc -n harbor

# 3. Ingress 가 생성되고 Push 용 어노테이션 4종이 적용되었는지 확인
kubectl describe ingress -n harbor harbor-ingress | grep -A10 Annotations

# 4. 레지스트리 API 응답 확인 (200 또는 401 이면 정상)
curl -sI http://data-layer-harbor/v2/ | head -1

# 5. Core Probe 완화 패치가 반영되었는지 확인 (timeoutSeconds=5)
kubectl get deploy -n harbor harbor-core \
  -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.timeoutSeconds}{"\n"}'
```

---
</br>

## 2️⃣ 워크로드 → Helm 차트 (300 이후 ~)

```bash
# 테라폼/Helm 프로젝트 디렉토리 이동
cd /project/Infrastructure-as-Code-Terraform.kubernetes
```

---

### 🔹1. 300-data-layer-base
- **data-layer 워크로드 공용 오브젝트 프로비저닝**
  (`Namespace` 1 / `ConfigMap` 1 / `Secret` 2 / `ClusterRoleBinding` 1)

```bash
# =====================================================
# 300-data-layer-base 배포
# =====================================================

# global.* 값 주입 + Helm 문법/스키마 검증
helm lint 300-data-layer-base -f values.common.yaml

# 렌더링 결과 확인
helm template data-layer-base 300-data-layer-base -f values.common.yaml


# 생성 오브젝트 수 확인
# Namespace 1 / Secret 2 / ConfigMap 1 / ClusterRoleBinding 1
# Secret 사이 `---` 누락 여부 확인
helm template data-layer-base 300-data-layer-base -f values.common.yaml \
  | kubectl apply --dry-run=client -f - -o name


# Helm Release는 default namespace에 관리
# data-layer Namespace는 차트가 직접 생성
helm install data-layer-base ./300-data-layer-base \
  -f values.common.yaml \
  -n default


# =====================================================
# 검증
# =====================================================

# 1. Helm Release 상태
helm -n default ls
# → STATUS = deployed


# 2. Namespace 생성 확인
kubectl get ns data-layer
# → STATUS = Active


# 3. 공용 ConfigMap / Secret 확인
kubectl -n data-layer get \
  cm/data-layer-env \
  secret/data-layer-secrets \
  secret/data-layer-postgres-app-user
# → DATA = 63 / 8 / 2

# Base Chart 소유 리소스 확인
kubectl -n data-layer get cm,secret
# → ConfigMap 1개 + Secret 2개
# → kube-root-ca.crt는 Kubernetes 자동 생성


# 서비스별 ConfigMap은 각 차트에서 관리
# → 301 Kafka
# → 302 Monitoring
# → 307 Pipeline


# 중복 Secret 키가 없는지 확인
# MinIO / PostgreSQL 계정은 원본 Secret을 직접 참조
kubectl -n data-layer get secret data-layer-secrets \
  -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}' \
  | grep -cE 'MINIO_ROOT|COLLECTOR_DB'
# → 0


# 중복 ConfigMap 키가 없는지 확인
# 서비스별 환경변수 이름은 configMapKeyRef로 변환
kubectl -n data-layer get cm data-layer-env \
  -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}' \
  | grep -cE 'LINEAGE_PG_DSN|TCP_SOCKET_PG_DSN|TCP_SOCKET_DLQ_TOPIC|GF_SERVER_ROOT_URL'
# → 0


# 4. 파생 접속값 확인
# values가 아닌 _helpers.tpl에서 생성
kubectl -n data-layer get cm data-layer-env \
  -o jsonpath='{.data.KAFKA_BOOTSTRAP}'
# → Kafka Broker Node IP

kubectl -n data-layer get cm data-layer-env \
  -o jsonpath='{.data.COLLECTOR_DB_HOST}'
# → 303 PostgreSQL CNPG RW Service

kubectl -n data-layer get cm data-layer-env \
  -o jsonpath='{.data.CDM_OBJSTORE_ENDPOINT}'
# → 301 MinIO Service


# 5. PostgreSQL App User Secret 타입 확인
# CNPG Role 생성과 API가 동일한 Secret을 사용
kubectl -n data-layer get secret \
  -o custom-columns=NAME:.metadata.name,TYPE:.type
# → data-layer-secrets = Opaque
# → data-layer-postgres-app-user = kubernetes.io/basic-auth


# 6. ClusterRoleBinding 확인
kubectl get clusterrolebinding data-layer-default-admin
# → data-layer:default ServiceAccount → cluster-admin


# 7. Helm 렌더링 결과와 클러스터 상태 비교
# 출력 없음 + exit 0 = 동일
helm template data-layer-base 300-data-layer-base \
  -f values.common.yaml \
  | kubectl diff -f -
```

---

### 🔹2. 301-hadoop
- **HDFS HA (NameNode 2 + ZKFC, JournalNode 3, ZooKeeper 3, DataNode 3) → hostNetwork + 정적 Local PV**

```bash
# =====================================================
# 0. 배포 전제
# =====================================================

# 노드 로컬 디렉터리 준비 (Local PV)
# Ansible hadoop_prereq 롤로 사전 생성
# 미생성 노드는 Local PV 마운트 실패로 Pod 기동 불가
- bin/start_hadoop_prereq.sh <ansible_dir> all
- 디렉터리: /data/hadoop-{zookeeper,journalnode,namenode,datanode}

# hostNetwork 포트 사전 확인 (노드별 중복 불가)
- NameNode: 8020/9870
- JournalNode: 8485/8480
- ZKFC: 8019
- DataNode: 9866/9867/9864
- ZooKeeper: 2181/2888/3888/7000
ss -lnt | grep -E ':(8020|9870|8485|8480|8019|986[467]|2181|2888|3888|7000)$'   # 빈 출력

# Hadoop 이미지 Harbor 사전 등록
# Hadoop 3.4.3 + ZooKeeper 3.9.5 / UID 1000
- ./scripts/build_and_push.sh v0.1.0 hadoop

# data-layer 기본 리소스 선행 배포
- 300-data-layer-base 선행 배포
- 노드/포트/nameservice: values.common.yaml의 global 설정 사용
- Service 없음 (hostNetwork → 노드 IP 직접 사용)


# =====================================================
# 1. Helm 배포
# =====================================================
helm lint 301-hadoop -f values.common.yaml
helm template hadoop 301-hadoop -f values.common.yaml
helm install hadoop ./301-hadoop -f values.common.yaml -n data-layer

# 최초 기동 시 HA 초기화 자동 수행 (약 2~3분)
# ZooKeeper → JournalNode → NameNode format/bootstrap → ZKFC → DataNode
# nn1의 bootstrapStandby retry/error는 nn0 기동 대기 중 발생하는 정상 로그
# 재기동 시 기존 fsimage가 있으면 format/bootstrap 생략


# =====================================================
# 2. 배포 상태 확인
# =====================================================
helm -n data-layer ls
helm -n data-layer status hadoop

# STATUS = deployed


# =====================================================
# 3. Pod / PVC / PV 확인
# =====================================================
kubectl -n data-layer get pod -l app.kubernetes.io/name=hadoop -o wide

# 11개 Running / Restart 0
# NameNode는 2/2 (NameNode + ZKFC)
# Pod IP = 노드 IP (hostNetwork)
# ordinal과 nodeNames 순서로 노드 고정

kubectl -n data-layer get pvc -l app.kubernetes.io/name=hadoop
kubectl get pv -l app.kubernetes.io/name=hadoop

# PVC 11개 Bound
# Local PV + claimRef로 Pod와 노드/디스크 고정


# =====================================================
# 4. HA 구성 확인
# =====================================================
# NameNode Active / Standby
kubectl -n data-layer exec hadoop-namenode-0 -c namenode -- hdfs haadmin -getAllServiceState

# Active 1대 / Standby 1대
# ZooKeeper 쿼럼
for i in 0 1 2; do kubectl -n data-layer exec hadoop-zookeeper-$i -- \
  bash -c 'exec 3<>/dev/tcp/127.0.0.1/2181; echo srvr >&3; grep -E "Mode|Zxid" <&3'; done

# Leader 1대 + Follower 2대
# Zxid 동기화 확인


# JournalNode EditLog 동기화
for ip in 192.168.56.38 192.168.56.39 192.168.56.40; do
  curl -s "http://$ip:8480/jmx?qry=Hadoop:service=JournalNode,name=Journal-datalayer" \
    | grep -oE '"(LastWrittenTxId|CurrentLagTxns)" ?: ?[0-9]+'
done

# 3대 LastWrittenTxId 동일 / CurrentLagTxns = 0


# DataNode / 블록 상태
kubectl -n data-layer exec hadoop-namenode-0 -c namenode -- hdfs dfsadmin -report \
  | grep -E 'Live datanodes|Dead datanodes|Under replicated|Missing blocks'

# Live 3 / Dead 0 / Under replicated 0 / Missing 0


# =====================================================
# 5. HDFS 쓰기 / 읽기 검증
# =====================================================
kubectl -n data-layer exec hadoop-namenode-0 -c namenode -- bash -c \
  'echo ok > /tmp/t && hdfs dfs -mkdir -p /smoke && hdfs dfs -put -f /tmp/t /smoke/t \
   && hdfs dfs -cat /smoke/t && hdfs fsck /smoke/t | grep -E "Status|Average block replication"'

# ok 출력
# Status: HEALTHY
# Average block replication: 3.0

kubectl -n data-layer exec hadoop-namenode-0 -c namenode -- hdfs dfs -rm -r -skipTrash /smoke

# 접속 정보
# fs.defaultFS = hdfs://datalayer
# 클라이언트는 nn0/nn1 주소가 포함된 hdfs-site.xml 필요
# Web UI: http://192.168.56.38:9870 / http://192.168.56.39:9870
# HDFS 슈퍼유저: hadoop
# 사용자 디렉터리는 /user/<계정> 생성 후 chown 필요


# =====================================================
# 6. NameNode 자동 페일오버 검증
# =====================================================
# Active 삭제 → ZKFC가 Standby를 Active로 승격
# 기존 Local PV를 사용하므로 데이터/포맷 상태 유지
kubectl -n data-layer delete pod hadoop-namenode-0

kubectl -n data-layer exec hadoop-namenode-1 -c namenode -- \
  hdfs haadmin -getAllServiceState

# s1:8020 active / ap:8020 standby


# 노드 장애 시
# Local PV 특성상 다른 노드로 Pod 이동하지 않음
# NameNode 1대가 서비스 유지
# DataNode는 replication=3으로 데이터 보호
# 노드 복구 후 기존 디스크에서 Pod 재기동


# =====================================================
# 7. 운영
# =====================================================
# 설정 변경 시 OnDelete → helm upgrade만으로 Pod 재기동되지 않음
# NameNode는 Standby → 확인 → Active 순으로 순차 재기동
# JournalNode / ZooKeeper도 쿼럼 유지하며 한 대씩 재기동

helm upgrade hadoop ./301-hadoop -f values.common.yaml -n data-layer
kubectl -n data-layer delete pod hadoop-namenode-1

# 메모리: 현재 requests 미설정(BestEffort)
# 메모리 부족 시 values.yaml의 JVM heap부터 조정
ssh root@ap free -m

# 삭제 시 Local PV 데이터는 Retain으로 유지
# 완전 초기화 시 모든 노드의 /data/hadoop-* 데이터 삭제
helm uninstall hadoop -n data-layer
kubectl -n data-layer delete pvc -l app.kubernetes.io/name=hadoop
```

---

### 🔹3. 301-kafka
- **Kafka(KRaft) 3-Broker + 운영 도구 3종**

```bash
# =====================================================
# 0. 배포 전제
# =====================================================

# 1. 브로커 노드 디스크 사전 생성
     - Ansible kafka_prereq 실행 → 각 노드에 디렉토리 생성
     - /data/kafka-broker
     - /data/kafka-controller
     - 권한: root:root 2770

# 2. hostNetwork 포트 확인
     - 9092 / 9093 / 9094 / 9404 는 노드에서 사용 중이면 안 됨

# 3. Harbor 이미지 준비
     - kafka / schema-registry / kafka-ui / kafka-exporter

# 4. 300-data-layer-base 선행 배포
     - kafka-config / kafka-jmx-exporter ConfigMap 필요


# =====================================================
# 1. Helm 배포
# =====================================================

# values.common.yaml → global.* 공통값 주입
helm lint 301-kafka -f values.common.yaml

# 렌더링 결과 확인
helm template kafka 301-kafka -f values.common.yaml

# Kafka 배포
helm install kafka ./301-kafka -f values.common.yaml -n data-layer


# =====================================================
# 2. 배포 상태 (검증)
# =====================================================

helm -n data-layer ls
helm -n data-layer status kafka

→ STATUS = deployed


# =====================================================
# 3. Kafka Broker 확인 (검증)
# =====================================================

# StatefulSet + hostNetwork 확인
# → Broker 1개씩 지정 노드에 배치
# → Pod IP = Node IP
kubectl -n data-layer get pod -l app=kafka -o wide

# 예:
# kafka-0 → ap
# kafka-1 → s1
# kafka-2 → s2


# =====================================================
# 4. Local PV / PVC 확인 (검증)
# =====================================================

# Broker당 data / metadata PVC 2개
kubectl -n data-layer get pvc | grep kafka
→ Bound × 6

# 실제 Local PV 확인
kubectl get pv -l app.kubernetes.io/name=kafka

# StorageClass 확인
kubectl get sc kafka-local

→ no-provisioner / Retain


# =====================================================
# 5. KRaft Quorum 확인 (검증)
# =====================================================

kubectl -n data-layer exec kafka-0 -- \
  /opt/kafka/bin/kafka-metadata-quorum.sh \
  --bootstrap-server localhost:9092 describe --status

→ CurrentVoters = 3
→ LeaderId 정상


# =====================================================
# 6. Topic / Replication 확인 (검증)
# =====================================================

# Topic 목록
kubectl -n data-layer exec kafka-0 -- \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list

# 계약 Topic + Kafka 내부 Topic 확인

# Under-Replicated Partition 확인
kubectl -n data-layer exec kafka-0 -- \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --describe --under-replicated-partitions

→ 빈 출력 = URP 0 = 복제 정상


# =====================================================
# 7. 운영 도구 확인 (검증)
# =====================================================

kubectl -n data-layer rollout status \
  deploy/schema-registry \
  deploy/kafka-ui \
  deploy/kafka-exporter

→ 3개 모두 successfully rolled out

kubectl -n data-layer get svc \
  schema-registry kafka-ui kafka-exporter

# 브로커에는 Service 가 없다 (hostNetwork → 노드 IP:9092 직결 — 301-kafka README '브로커에는 Service 가 없다')
→ Schema Registry 9096
→ Kafka UI 9095
→ Kafka Exporter 9097


# =====================================================
# 8. Kafka UI 외부 접속 (검증)
# =====================================================

# Host 기반 Ingress 확인
kubectl -n data-layer get ingress kafka-ui

# HTTP 응답 확인
curl -s -o /dev/null -w '%{http_code}\n' \
  -H 'Host: data-layer-kafka-ui' \
  http://192.168.56.240/

→ 200


# =====================================================
# 9. Node / JMX Exporter 확인 (검증)
# =====================================================

# hostNetwork 포트 확인
ss -lnt | grep -E ':(909[2-4]|9404)$'

→ 9092 / 9093 / 9094 / 9404 LISTEN

# Broker JVM Metrics 확인
curl -s http://192.168.56.38:9404/metrics | head -3

→ JMX Exporter 메트릭 출력
```

---

### 🔹4. 301-minio (s3)
- **MinIO 단일 인스턴스**

```bash
# =====================================================
# 0. 배포 전제
# =====================================================

# Longhorn StorageClass 준비
# Node 장애 시 Pod 자동 재기동 정책 적용
     - longhorn StorageClass 존재
     - nodeDownPodDeletionPolicy 적용

# Harbor에 MinIO 이미지 사전 등록
     - minio (quay.io/minio/minio 재호스팅, mc 동봉)

# data-layer 기본 리소스 선행 배포
# MinIO 인증정보는 data-layer-secrets 사용
     - 300-data-layer-base 선행 배포
     - data-layer-secrets 의 MINIO_ROOT_USER / MINIO_ROOT_PASSWORD 사용


# =====================================================
# 1. Helm 배포
# =====================================================

# 공통 values 적용 및 Chart 검증
helm lint 301-minio -f values.common.yaml

# 렌더링 결과 확인
helm template minio 301-minio -f values.common.yaml

# MinIO 배포
helm install minio ./301-minio -f values.common.yaml -n data-layer


# =====================================================
# 2. 배포 상태 (검증)
# =====================================================

helm -n data-layer ls
helm -n data-layer status minio

→ STATUS = deployed


# =====================================================
# 3. Pod / PVC / Service 확인 (검증)
# =====================================================

kubectl -n data-layer get pod,pvc,svc -l app=minio -o wide

→ Pod Running
→ PVC Bound (Longhorn / 20Gi)
→ Service ClusterIP :9000
→ Console 비활성화

# Service 엔드포인트 확인
kubectl -n data-layer get endpoints minio

→ <Pod IP>:9000


# =====================================================
# 4. Longhorn 볼륨 확인 (검증)
# =====================================================

# PVC에 연결된 볼륨 상태 확인
kubectl -n longhorn-system get volumes.longhorn.io \
  $(kubectl -n data-layer get pvc minio-data -o jsonpath='{.spec.volumeName}')

→ attached / healthy

# Replica 분산 확인
kubectl -n longhorn-system get replicas.longhorn.io -o wide | grep minio

→ Replica 2개가 서로 다른 노드에 존재


# =====================================================
# 5. S3 API 확인 (검증)
# =====================================================

# MinIO API Ready 상태 확인
kubectl -n data-layer exec deploy/minio -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://localhost:9000/minio/health/ready

→ 200

# S3 API 및 인증 확인
kubectl -n data-layer exec deploy/minio -- sh -c \
  'mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" && mc ready local'

→ The cluster is ready

# 클러스터 내부 접속 주소
→ http://minio.data-layer.svc.cluster.local:9000


# =====================================================
# 6. 노드 장애 페일오버 (검증)
# =====================================================

# Longhorn 장애 대응 정책 확인
kubectl -n longhorn-system get setting node-down-pod-deletion-policy

→ delete-both-statefulset-and-deployment-pod

# MinIO 실행 노드 장애 시 페일오버 확인
kubectl -n data-layer get pod -l app=minio -o wide -w

→ Pod 삭제 → 다른 노드 재스케줄 → 볼륨 재연결 → 서비스 복구
→ 데이터 유지
```

---

### 🔹5. 301-elasticsearch (Elasticsearch)
- **Elasticsearch 3-Node 클러스터 (master+data)**
- **hostNetwork + Local PV 사용, 데이터 복제는 Elasticsearch가 담당**

```bash
# =====================================================
# 0. 배포 전제
# =====================================================

# 1. 노드 디스크 준비
# → 각 노드에 ES 데이터 디렉토리 생성
# → Ansible elasticsearch_prereq 실행
# → /data/elasticsearch
# → root:root / 2770

# 2. hostNetwork 포트 확인
# → 9200(HTTP), 9300(Transport) 미사용 확인

# 3. Harbor 이미지 준비
# → elasticsearch 이미지 빌드 및 Push
# → build_and_push.sh <TAG> elasticsearch

# 4. 300-data-layer-base 선행 배포
# → data-layer Namespace 생성
# → ES 설정은 차트에서 직접 주입

# 5. 커널 설정
# → vm.max_map_count >= 262144
# → 미달 시 ES 부트스트랩 검사 실패


# =====================================================
# 1. Helm 배포
# =====================================================

# values.common.yaml → global.* 주입
# → 노드 IP는 global.nodes에서 파생
helm lint 301-elasticsearch -f values.common.yaml

# 렌더링 확인
helm template elasticsearch 301-elasticsearch -f values.common.yaml

# Elasticsearch 배포
helm install elasticsearch ./301-elasticsearch \
  -f values.common.yaml \
  -n data-layer


# =====================================================
# 2. 배포 상태 확인
# =====================================================

helm -n data-layer ls
helm -n data-layer status elasticsearch

→ STATUS = deployed


# =====================================================
# 3. ES 노드 확인
# =====================================================

# StatefulSet + hostNetwork 확인
# → ordinal과 nodeNames를 1:1 매핑
# → Pod IP = Node IP
kubectl -n data-layer get pod -l app=elasticsearch -o wide

# 예:
# elasticsearch-0 → ap
# elasticsearch-1 → s1
# elasticsearch-2 → s2


# =====================================================
# 4. Local PV / PVC 확인
# =====================================================

# 노드별 data PVC 확인
kubectl -n data-layer get pvc -l app.kubernetes.io/name=elasticsearch

→ Bound × 3

# Local PV 확인
# → 각 PVC가 해당 노드의 PV에 고정
kubectl get pv -l app.kubernetes.io/name=elasticsearch

# StorageClass 확인
# → 동적 프로비저닝 없음 / 삭제 후 PV 유지
kubectl get sc elasticsearch-local

→ no-provisioner / Retain


# =====================================================
# 5. 클러스터 / 마스터 확인
# =====================================================

# 클러스터 상태 확인
curl -s '192.168.56.38:9200/_cluster/health?pretty'

→ status = green
→ number_of_nodes = 3

# 노드 및 마스터 확인
curl -s '192.168.56.38:9200/_cat/nodes?v'

→ 3개 노드
→ master 열의 * = 현재 마스터


# =====================================================
# 6. 복제 확인
# =====================================================

# 테스트 인덱스 생성
# → replica 1개 생성
curl -s -X PUT '192.168.56.38:9200/_test' \
  -H 'Content-Type: application/json' \
  -d '{"settings":{"number_of_shards":1,"number_of_replicas":1}}'

# Primary / Replica 배치 확인
# → 서로 다른 노드에 배치되어야 함
curl -s '192.168.56.38:9200/_cat/shards/_test?v'

→ p / r 각 1개
→ STARTED
→ 서로 다른 node

# 테스트 인덱스 삭제
curl -s -X DELETE '192.168.56.38:9200/_test'


# =====================================================
# 7. Service 확인
# =====================================================

# HTTP 9200 접근용 ClusterIP
# → Ready 노드의 9200으로 연결
kubectl -n data-layer get svc,endpoints elasticsearch

→ 9200 / ENDPOINTS 3개

# 9300 Transport는 Service 없이 노드 IP로 직접 통신
# → seed_hosts에 각 노드 IP 사용


# =====================================================
# 8. 노드 포트 확인
# =====================================================

# hostNetwork 포트 확인
ss -lnt | grep -E ':(9200|9300)$'

→ 9200 / 9300 LISTEN
```


---

### 🔹6. 301-neo4j (Graph DB)
- **Neo4j 단일 인스턴스(Community)**
- **Deployment(Recreate) + Longhorn RWO PVC**
- **장애 시 Pod 재스케줄 + Longhorn 볼륨 재연결**

```bash
# =====================================================
# 0. 배포 전제
# =====================================================

# 1. Longhorn 준비
# → StorageClass longhorn
# → 3노드 Instance Manager Ready
# → Local PV가 아니므로 노드 디렉토리 생성 불필요

# 2. Harbor 이미지 준비
# → neo4j 이미지 빌드 및 Push
# → build_and_push.sh <TAG> neo4j

# 3. 300-data-layer-base 선행 배포
# → Neo4j 계정은 Secret에서 주입
# → 사용자명은 neo4j 고정
# → NEO4J_AUTH로 조립

# 4. 접속 주소
# → ClusterIP Service의 내부 DNS 사용
# → 300에서 PLATFORM_NEO4J_URI로 제공
# → 307 Graph Consumer가 사용


# =====================================================
# 1. Helm 배포
# =====================================================

# 공통 설정 검증
helm lint 301-neo4j -f values.common.yaml

# 렌더링 확인
helm template neo4j 301-neo4j -f values.common.yaml

# Neo4j 배포
helm install neo4j ./301-neo4j \
  -f values.common.yaml \
  -n data-layer


# =====================================================
# 2. 배포 상태 확인
# =====================================================

helm -n data-layer ls
helm -n data-layer status neo4j

→ STATUS = deployed


# =====================================================
# 3. Pod / PVC 확인
# =====================================================

# Pod / PVC / Service 상태 확인
# → Pod 1개
# → PVC 1개
# → ClusterIP로 내부 접근
kubectl -n data-layer get pod,pvc,svc -l app=neo4j -o wide

→ Pod 1/1 Running
→ PVC Bound
→ Service 7687 / 7474

# Longhorn 볼륨 상태 확인
# → 볼륨 Attached + Healthy 확인
kubectl -n longhorn-system get volumes.longhorn.io \
  -o custom-columns=NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness,NODE:.status.currentNodeID

→ attached / healthy


# =====================================================
# 4. 접속 확인
# =====================================================

# 컨테이너 내부에서 Neo4j 연결 확인
# → 환경변수는 컨테이너 내부에서 확장
kubectl -n data-layer exec deploy/neo4j -- \
  sh -c 'cypher-shell -u "$PLATFORM_NEO4J_USER" -p "$PLATFORM_NEO4J_PASSWORD" "RETURN 1"'

→ 1

# Browser / Bolt 로컬 접속
# → 외부 노출 없이 port-forward 사용
kubectl -n data-layer port-forward svc/neo4j 7474:7474 7687:7687

# → Browser: http://localhost:7474
# → Bolt: bolt://localhost:7687


# =====================================================
# 5. Graph Consumer 전환
# =====================================================

# URI 변경 후 Consumer 재기동
# → 300 변경은 자동 롤아웃되지 않음
helm upgrade data-layer-base ./300-data-layer-base \
  -f values.common.yaml \
  -n default

kubectl -n data-layer rollout restart deploy/cdm-consumer-graph

# 새 URI 확인
kubectl -n data-layer exec deploy/cdm-consumer-graph -- \
  env | grep NEO4J_URI

→ bolt://neo4j.data-layer.svc.cluster.local:7687


# =====================================================
# 6. 노드 장애 전환
# =====================================================

# Pod 이동 확인
# → Node 장애 시 Pod 재스케줄
# → Longhorn PVC를 새 Node에 재연결
kubectl -n data-layer get pod -l app=neo4j -o wide -w

→ 다른 Node에서 Running
→ 동일 PVC 연결

# 예상 복구 시간은 Node 장애 감지 + Pod 퇴거 + 볼륨 재연결에 따라 결정
# → 상세 검증은 301-minio RUNBOOK과 동일
```

---

### 🔹7. 302-monitoring

- 모니터링 3종 (`Alloy` / `Prometheus` / `Grafana`) 프로비저닝
  - 수집 → `Alloy` (데몬셋)
  - 메트릭 시계열 저장 → `Prometheus` (디플로이먼트)
  - 시각화 → `Grafana` (디플로이먼트)
- `Prometheus/Grafana` 는 `values.yaml` 의 `nodeNames(nodeAffinity)`로 배치 노드를 고정
- `Alloy` 는 `DaemonSet` 이라 `nodeAffinity` 대상이 아님
- **설정 `ConfigMap` 3종(`alloy-config`/`prometheus-config`/`grafana-datasource`)을 이 차트가 소유 → 파드의 `checksum` 어노테이션이 해시를 들고 있어 helm upgrade 만으로 자동 롤아웃**
- **사전 준비: `300-data-layer-base` 배포 완료 + `Harbor` 에 이미지 `push` 완료(`build_and_push.sh`)**


```bash
# 1. 302-monitoring 검증
# → 공용 값은 values.common.yaml에서 주입
helm lint 302-monitoring -f values.common.yaml
helm template monitoring 302-monitoring -f values.common.yaml

# 2. 302-monitoring 설치
# → data-layer Namespace에 배포
helm install monitoring ./302-monitoring -f values.common.yaml -n data-layer


[검증]
# 1. Helm Release 상태
# → STATUS = deployed
helm -n data-layer ls

# 2. 워크로드 상태
# → Alloy는 모든 Node에 1개 / Prometheus·Grafana는 1개
kubectl -n data-layer get ds/alloy deploy/prometheus deploy/grafana

# 3. Pod 배치 확인
# → Prometheus·Grafana는 지정 Node / Alloy는 전체 Node
kubectl -n data-layer get pod -o wide \
  -l app.kubernetes.io/part-of=data-layer

# 4. ConfigMap 및 Helm 소유권 확인
kubectl -n data-layer get cm \
  alloy-config prometheus-config grafana-datasource

kubectl -n data-layer get cm prometheus-config \
  -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}'

→ 결과가 monitoring인지 확인

# 5. PVC 상태
# → Prometheus·Grafana PVC가 Longhorn에 정상 바인딩됐는지 확인
kubectl -n data-layer get pvc prometheus-data grafana-data

# 6. Grafana → Prometheus 연결 확인
# → Service FQDN으로 설정됐는지 확인
kubectl -n data-layer get cm grafana-datasource \
  -o jsonpath='{.data.datasource\.yml}' | grep url

→ http://prometheus.data-layer.svc.cluster.local:9090

# 7. Prometheus Target 상태
# → 5개 Target이 모두 UP인지 확인
# → 모두 비어 있으면 Kubernetes API 조회 권한(RBAC) 확인
# http://data-layer-prometheus/targets

# 8. Grafana 자동 프로비저닝 확인
# → Prometheus Data Source 및 Dashboard 생성 여부 확인
# http://data-layer-grafana
```

---

### 🔹 8. 303-postgres

- **CNPG 기반 PostgreSQL 클러스터 배포**
  - `Cluster`와 `Database`를 선언하면 **CNPG Operator가 Pod / PVC / 복제 / Failover를 관리**한다.
  - PostgreSQL 인스턴스 2개(`Primary 1 + Replica 1`)를 배치한다.
  - 외부 접속은 MetalLB VIP `192.168.56.241:5432`를 사용한다.

- **DB 초기화**
  - `postInitApplicationSQL` → Extension / Schema / Table / Hypertable 생성
  - `Database CR` → `airflow` / `iceberg_catalog` DB 생성


- **설치 전제**
  - `103-cnpg` → CNPG CRD / Operator
  - `300-data-layer-base` → Namespace / Secret
  - 위 두 스택이 먼저 설치되어 있어야 한다.
  - PostgreSQL 이미지 태그는 CNPG가 인식할 수 있도록 `16.15-v0.1.0`처럼 **PostgreSQL 버전으로 시작해야 한다.**

- **주의**
  - `helm uninstall` 시 Cluster와 PVC가 삭제될 수 있으므로 **운영 데이터가 있는 환경에서는 주의한다.**

```bash
# 303-postgres 설치
helm install postgres ./303-postgres \
  -f values.common.yaml \
  -n data-layer


[검증]
# 1. PostgreSQL Cluster 상태
kubectl -n data-layer get cluster

# 2. Pod 및 Node 배치
kubectl -n data-layer get pod -o wide

# 3. Service 및 MetalLB VIP
kubectl -n data-layer get svc

# 4. Database 생성 상태
kubectl -n data-layer get database

# 5. heidiSQL 실제 접속 해보기

```


---

### 🔹 9. 304-airflow
- **Airflow 3.1.5** → `KubernetesExecutor` 기반
- **메타DB:** `CNPG PostgreSQL`(303-postgres)
- **로그:** `MinIO S3`(`301-minio` `airflow-logs`, 30일 `ILM`)
- **DAG/코드:** 각 노드 `hostPath` `/project/data_pipeline/data_layer_airflow`
  - `ap`: 원본
  - `s1`/`s2`: `rsync` 사본

```bash
# =====================================================
# 0. 배포 전제
# =====================================================

# 필수 선행 스택
# - 300-data-layer-base : 공통 Secret/ConfigMap, 태스크 파드 권한
# - 303-postgres        : Airflow 메타DB
# - 301-minio           : airflow-logs / config 버킷

# DAG/코드를 모든 노드에 동기화
bin/start_airflow_repo_prereq.sh <ansible_dir> all

for n in ap s1 s2; do
  ssh root@$n 'echo -n "$(hostname): "; ls /project/data_pipeline/data_layer_airflow/dags | wc -l'
done

# requirements.txt 변경 시에만 Airflow 이미지 재빌드
./scripts/build_and_push.sh v0.1.0 airflow

# MinIO 버킷 및 config 시드 확인
POD=$(kubectl -n data-layer get pod -l app=minio -o jsonpath='{.items[0].metadata.name}')
kubectl -n data-layer exec $POD -- mc ls local
kubectl -n data-layer exec $POD -- mc ls -r local/config


# =====================================================
# 1. Helm 배포
# =====================================================

helm lint 304-airflow -f values.common.yaml
helm template airflow 304-airflow -f values.common.yaml | kubectl apply --dry-run=server -f -

helm install airflow ./304-airflow \
  -f values.common.yaml \
  -n data-layer \
  --timeout 10m

# 초기 DB migration Hook 완료까지 최대 10분 대기
# --wait / --atomic은 post-hook과 Ready 순환 대기로 사용하지 않음


# =====================================================
# 2. 배포 상태 확인
# =====================================================

helm -n data-layer status airflow

kubectl -n data-layer get deploy,job,svc,ing \
  -l app.kubernetes.io/name=airflow

kubectl -n data-layer get pod \
  -l app.kubernetes.io/name=airflow -o wide

# 정상 상태
# - api-server      1/1
# - scheduler       1/1
# - dag-processor   1/1
# - triggerer       0/0
# - airflow-init    Completed

# 초기화 Job 확인
kubectl -n data-layer logs job/airflow-init | tail -5


# =====================================================
# 3. Airflow 정상 동작 확인
# =====================================================

# API / 전체 헬스
curl -s http://data-layer-airflow/api/v2/monitor/health

# Scheduler 헬스
kubectl -n data-layer exec deploy/airflow-scheduler -- \
  curl -s localhost:8974/health

# DAG 마운트 및 Import 상태
kubectl -n data-layer exec deploy/airflow-dag-processor -- \
  ls /opt/airflow/dags

kubectl -n data-layer exec deploy/airflow-dag-processor -- \
  airflow dags list

kubectl -n data-layer exec deploy/airflow-dag-processor -- \
  airflow dags list-import-errors

# Variable / Connection 확인
kubectl -n data-layer exec deploy/airflow-scheduler -- \
  airflow variables get collector_db_query

kubectl -n data-layer exec deploy/airflow-scheduler -- \
  airflow connections get collector_db

kubectl -n data-layer exec deploy/airflow-scheduler -- \
  airflow connections get minio_logs


# =====================================================
# 4. DAG 실행 검증
# =====================================================

# DAG 활성화 및 수동 실행
kubectl -n data-layer exec deploy/airflow-scheduler -- \
  airflow dags unpause Batch_Data_Collector

kubectl -n data-layer exec deploy/airflow-scheduler -- \
  airflow dags trigger Batch_Data_Collector

# KubernetesExecutor: Task마다 Worker Pod 생성
kubectl -n data-layer get pod \
  -l app.kubernetes.io/component=worker -w

# Worker 실행 로그 확인
kubectl -n data-layer logs <worker-pod>


# =====================================================
# 5. MinIO 로그 확인
# =====================================================

# Worker 종료 후 S3 로그 업로드 확인
POD=$(kubectl -n data-layer get pod -l app=minio -o jsonpath='{.items[0].metadata.name}')
kubectl -n data-layer exec $POD -- mc ls -r local/airflow-logs

# 30일 만료 정책 확인
kubectl -n data-layer exec $POD -- \
  mc ilm rule ls local/airflow-logs

# 로그가 없으면 Worker 로그와 Airflow UI의 S3 오류 확인


# =====================================================
# 6. DAG / 코드 반영
# =====================================================

# 코드 변경 → 이미지 재빌드 없이 전체 노드 동기화
bin/start_airflow_repo_prereq.sh <ansible_dir> sync

# 모든 노드의 hostPath가 동일해야 함
# Task Pod는 실행된 노드의 hostPath를 사용

# requirements.txt 변경 시에만 이미지 재빌드


# =====================================================
# 7. 운영
# =====================================================

# values 변경 적용
helm upgrade airflow ./304-airflow \
  -f values.common.yaml \
  -n data-layer \
  --timeout 10m

# 실패한 Worker Pod 정리
kubectl -n data-layer delete pod \
  -l app.kubernetes.io/component=worker \
  --field-selector=status.phase=Failed

# Deferrable Operator 사용 시 triggerer 필요
# DELETE_WORKER_PODS_ON_FAILURE=False → 실패 Worker는 남겨둠

# Airflow 삭제
# 메타DB / MinIO 로그 / hostPath 코드는 유지
helm uninstall airflow -n data-layer
kubectl -n data-layer delete job airflow-init
```

---

### 🔹 10. 304-airflow-rsync
- **Airflow DAG/코드 디렉토리 노드 간 동기화**
  - 원본 `ap`의 `/project/data_pipeline/data_layer_airflow`를 `inotify`로 감시하고, 변경 시 `rsync over SSH`로 `s1/s2`에 전파
  - 변경이 없어도 `intervalSeconds(1800s)`마다 전체 동기화하여 누락 및 노드 복귀를 보완

```bash
1. 304-airflow-rsync 실행
helm lint 304-airflow-rsync -f values.common.yaml                                  → 차트 문법 / values 스키마 검증
helm template airflow-rsync ./304-airflow-rsync -f values.common.yaml              → 렌더 결과 확인 (TARGETS IP·이미지 태그)
helm install airflow-rsync ./304-airflow-rsync -f values.common.yaml -n data-layer → Sync Pod 배포

[검증]
# 1. Sync Pod가 원본 노드(ap)에 배치되고 READY 1/1(전 노드 동기화 성공)인지 확인
kubectl -n data-layer get pod -l app=airflow-rsync -o wide

# 2. 대상 노드별 동기화 결과 확인 (OK <ip> / FAIL <ip>)
kubectl -n data-layer logs deploy/airflow-rsync --tail=20

# 3. 대상 노드에 DAG가 실제로 전파되었는지 확인
for n in s1 s2; do ssh root@$n 'ls /project/data_pipeline/data_layer_airflow/dags | wc -l'; done
```



---

### 🔹 11. 305-api

- **data-layer-api 관리 화면 + REST API**
- Deployment 1 / Service 1 / Ingress 1 / PVC 없음
- replicas **1 고정** → DQ가 매퍼 Pod를 제어하므로 동시성 충돌 방지
- `hostAliases` → `global.ingressVip` 기준으로 내부 서비스 이름 해석

```bash
# =====================================================
# 1. 배포
# =====================================================

helm lint 305-api -f values.common.yaml
helm template api ./305-api -f values.common.yaml
helm install api ./305-api -f values.common.yaml -n data-layer

# =====================================================
# 2. 검증
# =====================================================

helm -n data-layer status api
# → STATUS = deployed

kubectl -n data-layer get deploy,svc,ing \
  -l app=data-layer-api
# → Deployment 1/1 · Service :8090 · Ingress data-layer-api

# hostAliases 확인
kubectl -n data-layer exec deploy/data-layer-api -- \
  getent hosts data-layer-grafana

# API 응답
curl -s http://data-layer-api/health
# → 200
```

---

### 🔹 12. 306-cdc

- **Kafka Connect + Debezium CDC 워커**
- Deployment 1 / replicas **2**
- Service `cdc-connect:8083` → Kafka Connect REST API
- Connect 상태는 **Kafka 내부 토픽 3종**에 저장
- 실제 Connector 등록은 **관리 화면 또는 REST API**에서 수행

```bash
# =====================================================
# 1. Helm 배포
# =====================================================

helm lint 306-cdc -f values.common.yaml
helm template cdc ./306-cdc -f values.common.yaml

helm install cdc ./306-cdc \
  -f values.common.yaml \
  -n data-layer

# [주의] Debezium Plugin 스캔으로 첫 Ready까지 수 분 소요 가능
# → startupProbe 최대 300초


# =====================================================
# 2. 배포 상태 확인
# =====================================================

helm -n data-layer status cdc
# → STATUS = deployed

kubectl -n data-layer get deploy,pod,svc \
  -l app=cdc-connect -o wide

# → Worker 2개 2/2 Ready
# → 가능하면 서로 다른 노드에 배치


# =====================================================
# 3. Kafka Connect REST 확인
# =====================================================

kubectl -n data-layer exec deploy/cdc-connect -- \
  curl -s localhost:8083/

# → Connect 버전 / Kafka Cluster 정보 확인

kubectl -n data-layer exec deploy/cdc-connect -- \
  curl -s localhost:8083/connectors

# → [] : 아직 Connector 미등록


# =====================================================
# 4. Connect 내부 토픽 확인
# =====================================================

kubectl -n data-layer exec kafka-0 -- \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --list | grep connect-

# → connect-configs
# → connect-offsets
# → connect-status
#
# Connector 설정 / Offset / 상태 정보를 Kafka에 저장
```


---


### 🔹 13. 307-pipeline

- **CDM 데이터 파이프라인 워커**
- Deployment **13개**
  - Mapper 8
  - Consumer 3
  - Lineage 1
  - TCP Collector 1
- PVC / Probe 없음
- TCP Collector는 `hostNetwork`로 실행**
- Mapper는 `cdm.mapper/module` 라벨을 사용 → 305-api의 DQ 제어 대상

```bash
# =====================================================
# 1. Helm 배포
# =====================================================

helm lint 307-pipeline -f values.common.yaml
helm template pipeline ./307-pipeline -f values.common.yaml

helm install pipeline ./307-pipeline \
  -f values.common.yaml \
  -n data-layer


# =====================================================
# 2. 배포 상태 확인
# =====================================================

helm -n data-layer status pipeline
# → STATUS = deployed


# =====================================================
# 3. Mapper 확인
# =====================================================

kubectl -n data-layer get pod \
  -l app=cdm-mapper \
  -L cdm.mapper/module

# → Mapper 8개 Running
# → MODULE 컬럼으로 Mapper 종류 확인


# =====================================================
# 4. Consumer / Lineage 확인
# =====================================================

kubectl -n data-layer get deploy \
  -l app.kubernetes.io/component=cdm-consumer

# → rdb / graph / warehouse 각 1개

kubectl -n data-layer get deploy cdm-lineage-consumer

# → 1/1


# =====================================================
# 5. TCP Collector 확인
# =====================================================

kubectl -n data-layer get pod \
  -l app=tcp-socket-collector -o wide

# → NODE=s2
# → hostNetwork 사용 → Pod IP가 아닌 Node IP로 동작


# =====================================================
# 6. 파이프라인 상태 확인
# =====================================================

# 별도 Probe가 없으므로 Kafka Consumer Lag으로 확인
# → Grafana > Kafka Dashboard > Consumer Group Lag

# Lag 증가 지속 → Consumer 처리 지연/장애 확인
```

---


### 🔹 14. 308-spark

- **Spark on Kubernetes** → K8s가 리소스 관리
- **Workbench 1개** → Spark Driver 역할
- **Executor는 Job 실행 시 Pod로 생성 후 종료**
- **Iceberg Catalog = PostgreSQL / 데이터 = HDFS**
- **Spark 설정 + HDFS 설정은 ConfigMap으로 주입**
- **PySpark 코드는 hostPath + rsync로 노드 간 공유**

```bash
# =====================================================
# 1. 이미지 빌드
# =====================================================

/project/data_pipeline/scripts/build_and_push.sh v0.1.0 spark

# → Workbench / Executor가 동일 이미지 사용


# =====================================================
# 2. Helm 배포
# =====================================================

# Helm 설정 검증
helm lint 308-spark -f values.common.yaml

# 렌더링 확인
helm template spark ./308-spark -f values.common.yaml

# Spark Workbench 배포
helm install spark ./308-spark \
  -f values.common.yaml \
  -n data-layer

# jobs.hostPath가 있는 Node에만 스케줄 가능
# → ap의 코드는 304-airflow-rsync가 다른 Node로 동기화


# =====================================================
# 3. 배포 상태 확인
# =====================================================

helm -n data-layer status spark
# → STATUS = deployed

# Workbench 상태 및 배치 Node 확인
kubectl -n data-layer get deploy,pod \
  -l app=spark-workbench -o wide

# → Workbench 1/1 Ready
# → nodeNames 중 하나에 배치

# Spark / HDFS 설정 확인
kubectl -n data-layer get cm \
  spark-defaults spark-hadoop-config

# → ConfigMap 2개


# =====================================================
# 4. 스모크 테스트
# =====================================================

# Spark → Iceberg Catalog → PostgreSQL / HDFS / Executor 확인
kubectl -n data-layer exec deploy/spark-workbench -- \
  spark-submit /opt/spark/jobs/smoke.py

# → Catalog 조회
# → 테스트 데이터 처리
# → 테스트 테이블 정리

# Job 실행 중 Executor 생성 확인
kubectl -n data-layer get pod \
  -l spark-role=executor -w

# → 실행 중 Executor Pod 생성
# → Job 종료 후 Pod 삭제


# =====================================================
# 5. 대화형 사용
# =====================================================

# Spark SQL
kubectl -n data-layer exec -it deploy/spark-workbench -- \
  spark-sql

# spark-sql> SHOW NAMESPACES IN cdm;

# PySpark
kubectl -n data-layer exec -it deploy/spark-workbench -- \
  pyspark

# 코드는 spark_jobs에 저장
# → 304-airflow-rsync가 각 Node로 동기화
# → 코드 변경 시 이미지 빌드 불필요

# Executor 크기는 Job별로 지정
# 예: Executor 4개 / 메모리 4GB
spark-submit \
  --conf spark.executor.instances=4 \
  --conf spark.executor.memory=4g \
  ...
```


---

### 🔹 15. 400-test-rdb

- **CDC 테스트용 RDB 4종** → Oracle / MSSQL / PostgreSQL / MySQL
- StatefulSet 4 / Service 4 / PVC 4
- 저장소: **local-path**
- 초기화 스크립트는 `files/`에서 관리
- 테스트 전용 → 공용 ConfigMap/Secret 사용하지 않음

```bash
# =====================================================
# 1. Helm 배포
# =====================================================

helm lint 400-test-rdb -f values.common.yaml
helm template test-rdb ./400-test-rdb -f values.common.yaml

helm install test-rdb ./400-test-rdb \
  -f values.common.yaml \
  -n data-layer \
  --timeout 20m

# ※ 첫 배포는 이미지 Pull + DB 초기화로 수 분 소요


# =====================================================
# 2. 배포 상태 확인
# =====================================================

helm -n data-layer status test-rdb
# → STATUS = deployed

kubectl -n data-layer get sts,pod,pvc,svc \
  -l app.kubernetes.io/component=test-rdb

# → DB 4종 1/1
# → PVC Bound
# → Service 4개


# =====================================================
# 3. CDC 초기화 확인
# =====================================================

# MSSQL
kubectl -n data-layer logs job/cdc-mssql-init
# → is_cdc_enabled=1

# Oracle
kubectl -n data-layer logs cdc-oracle-0 | grep '초기화 완료'
# → Debezium 계정 / LOGMINER / 보충 로깅 확인

# PostgreSQL
kubectl -n data-layer exec cdc-postgres-0 -- \
  psql -U cdc -d cdc -c '\dRp'
# → cdc_test_pub

# MySQL
kubectl -n data-layer exec cdc-mysql-0 -- \
  sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" \
  -e "SHOW GRANTS FOR cdc@\"%\""'
# → REPLICATION SLAVE / CLIENT


# =====================================================
# 4. 로컬 DB 접속
# =====================================================

kubectl -n data-layer port-forward svc/cdc-oracle 11521:1521
kubectl -n data-layer port-forward svc/cdc-mssql 11433:1433
kubectl -n data-layer port-forward svc/cdc-postgres 15432:5432
kubectl -n data-layer port-forward svc/cdc-mysql 13306:3306


# =====================================================
# [주의]
# =====================================================

# Oracle / PostgreSQL / MySQL 초기화
# → 빈 PVC에서 최초 1회만 수행
# → 초기 상태로 재생성하려면 PVC 삭제 후 재배포

# helm uninstall 시 PVC는 남음

# Oracle 메모리 부족 시
# → oracle.sgaTarget / pgaAggregateTarget 값을 낮춤
```


---
</br>

# 🧩 배포 전 필수 준비 사항

`Terraform`/`Helm` 이 모델링하지 못하는 **클러스터 밖 수동 단계**입니다. 빠지면 파드가 `Pending`/`CrashLoop` 에 걸리거나 **조용히 잘못 동작**합니다.

| 대상 | 먼저 해야 할 작업 | 담당 | 빠지면 |
|---|---|---|---|
| 노드 `/etc/hosts` | `data-layer-*` 이름 → Ingress VIP(`.240`) 1줄 등록 | Ansible `etc_hosts` (`bin/start_server_configuration.sh <경로> etc_hosts`) | 이미지 pull·Ingress 접속 전부 실패 |
| containerd | `data-layer-harbor:80` 을 insecure registry 로 신뢰 (`certs.d/data-layer-harbor:80/hosts.toml`) | Ansible `containerd` (`containerd_insecure_registries`) | 노드가 Harbor 에서 pull 불가 |
| BuildKit | `buildkitd` + Harbor 인증 파일 (`buildkit_registry_password` = `200-harbor/secrets.auto.tfvars` 의 `harbor_admin_password`) | Ansible `buildkitd` (`bin/start_buildkitd.sh`) | `build_and_push.sh` push 실패 |
| Longhorn (`100-base`) | open-iscsi / multipath / `/data/longhorn` | Ansible `longhorn_prereq` (`bin/start_longhorn.sh <경로> all`) | Longhorn 노드 `READY=False`, longhorn PVC Pending |
| `301-kafka` | `/data/kafka-broker` · `/data/kafka-controller` (root:root **2770**) | Ansible `kafka_prereq` (`bin/start_kafka_prereq.sh`) | 정적 Local PV 마운트 실패 → 브로커 기동 불가 |
| `301-hadoop` | `/data/hadoop-{zookeeper,journalnode,namenode,datanode}` (root:root **2770**) | Ansible `hadoop_prereq` (`bin/start_hadoop_prereq.sh`) | Local PV 마운트 실패 / DataNode chmod 실패 |
| `301-elasticsearch` | `/data/elasticsearch` (root:root **2770**), `vm.max_map_count ≥ 262144` | Ansible `elasticsearch_prereq` (`bin/start_elasticsearch_prereq.sh`) | Local PV 마운트 실패 / 부트스트랩 검사로 기동 거부 |
| `304-airflow` · `308-spark` | 3노드에 `/project/data_pipeline/data_layer_airflow` (root:root 0755) | Ansible `airflow_repo_prereq` (`bin/start_airflow_repo_prereq.sh <경로> all`) | `hostPath.type: Directory` 라 경로 없는 노드에서 파드가 아예 안 뜬다 |
| `304-airflow-rsync` | 원본 노드(ap) `/root/.ssh/id_ed25519` + 대상 노드(s1/s2) `authorized_keys` | Ansible 선행작업 (`ssh root@s1` 비대화형 접속이 되면 충분) | Sync Pod `READY 0/1` (동기화 실패 노드 존재) |
| hostNetwork 포트 | 노드에서 유일해야 한다 → `ss -lnt` 로 설치 전 확인 | 엔지니어 | 포트 충돌로 파드 CrashLoop |
| 이미지 | `200-harbor` apply 뒤 `build_and_push.sh <TAG>` 26종 전부 (태그 = `global.imageTag`, 303 은 `16.15-<TAG>`) | 엔지니어 (0단계 참조) | `ImagePullBackOff` |
| MinIO `config` 버킷 | 버킷은 `301-minio` hook Job 이 만들고, **설정 시드만** `mc pipe` 로 1회 주입 (`301-minio/README.md` '버킷') | 엔지니어 | 305/307 이 DQ 규칙·스키마를 못 읽는다 |
| 접속 PC `hosts` | `data-layer-*` 이름 → `192.168.56.240` | 엔지니어 | 브라우저 접속 불가 |

> hostNetwork 포트 목록 → Kafka `9092/9093/9094/9404`, Hadoop `8020/9870/8485/8480/8019/9866/9867/9864/2181/2888/3888/7000`, Elasticsearch `9200/9300`, Alloy `12345`, tcp-socket-collector(런타임 DB 값).

> 노드 디렉토리 권한이 **2770(setgid)** 인 이유 → `0770` 이면 kubelet 의 `fsGroup` 처리가 재실행마다 setgid 를 벗겨 다음 재기동 때 데이터 전체를 다시 chown 한다. Ansible `*_data_mode` 와 차트 값(예: hadoop `dfs.datanode.data.dir.perm=770`)은 한 쌍이다.

---
</br>

# 🏗️ Terraform 공통 설정 (versions.tf / providers.tf)

- 모든 스택(`100~200`)은 같은 `Terraform` 버전·같은 변수 관리 기준을 사용합니다.

## 1. Terraform / Provider

- `required_version = "1.15.8"` → CLI 버전 고정
- 범위 연산자(`>=`, `~>`) 금지 → 프로바이더·서드파티 차트 버전 전부 정확 고정
- **리소스가 없는 프로바이더는 선언하지 않는다**

| Provider | 사용 스택 | 용도 |
|---|---|---|
| `helm 3.2.0` | `100`, `101`, `102`, `103`, `200` | 서드파티 Helm Chart 설치 (local-path·Longhorn·MetalLB·ingress-nginx·CNPG·Harbor) |
| `kubernetes 2.38.0` | `102` | MetalLB CR (`IPAddressPool` / `L2Advertisement`) → `kubernetes_manifest` + `templatefile` |
| `harbor 3.10.21` | `200` | Harbor REST API → `data-layer` 프로젝트 public 설정 |

> `300` 이후는 Terraform 이 아니라 **Helm 차트** 이므로 프로바이더 표에 없습니다.
> 클러스터 접속은 전 스택 공통 `kubeconfig_path`(`~/.kube/config`) 하나입니다.

---

## 2. 변수 / `Secret` 관리

- 환경마다 달라야 하는 값은 **`variables.tf` 에 `default` 를 두지 않고 `terraform.tfvars` 에서 강제**합니다 (누락 시 `plan` 에서 실패).

| 파일 | 용도 |
|---|---|
| `variables.tf` | 변수 타입 · 한 줄 `description` (다중 행 `<<-EOT` 금지) |
| `terraform.tfvars` | 환경별 실제 값 (차트 버전, VIP, 노드 이름, 경로) |
| `secrets.auto.tfvars` | `sensitive = true` 변수 주입 → **현재 `200-harbor` 만** (`harbor_admin_password`) |
| `secrets.auto.tfvars.example` | 변수명·형식만 제공 |

---

## 3. `terraform.tfvars` (현재 값)

```hcl
# 100-base
local_path_chart_version = "0.0.37"    # 기본 StorageClass
longhorn_chart_version   = "1.11.3"
longhorn_data_path       = "/data/longhorn"
longhorn_replica_count   = 2

# 101-metallb
metallb_chart_version = "0.16.1"        # frrk8s.enabled=false 필수 (L2 만 사용)

# 102-ingress
ingress_nginx_chart_version = "4.15.1"
ingress_vip      = "192.168.56.240"     # values.common.yaml global.ingressVip / Ansible ingress_vip 와 동일
postgres_vip     = "192.168.56.241"     # 303-postgres values externalIp 와 동일
ingress_replicas = 2

# 103-cnpg
cnpg_chart_version = "0.29.0"           # = 오퍼레이터 1.30.0

# 200-harbor
harbor_chart_version = "1.18.4"         # = Harbor 2.14
harbor_host          = "data-layer-harbor"   # 이미지 이름 첫 마디 → 변경 시 Ansible/build_and_push.sh 와 같은 커밋
harbor_storage_class = "local-path"
harbor_node_name     = "s2"             # 컴포넌트 7종 + PVC 5종 전부 이 노드
```

---

## 4. `secrets.auto.tfvars`

```hcl
# 200-harbor
harbor_admin_password = "..."           # Ansible buildkit_registry_password 와 글자 그대로 같아야 한다
```

- ⚠ **이 저장소는 공개 전제** → `*.tfstate` · `*.auto.tfvars` 를 **일부러 gitignore 하지 않는다** (랩 자격증명, 운영자 결정)
- 실계정을 쓰는 순간 전제가 깨진다 → `.gitignore` 의 주석 4줄을 되살리고 자격증명 전량 교체
- `.terraform.lock.hcl` 은 커밋, `.terraform/` 은 무시

---

## 5. 핵심 원칙
- `variables.tf` = 정의 / `terraform.tfvars` = 값 / `secrets.auto.tfvars` = 민감 정보 / `default` = 없음
- `main.tf` 금지 → 파일 이름이 곧 목차 (`storage.tf`, `longhorn.tf`, `metallb-pool.tf`, `harbor-project.tf` …)
- `helm_release` values 는 인라인 `yamlencode()`
- 스택 간 값 전달은 `terraform output` 이 아니라 **같은 값을 같은 커밋에서** (아래 '같은 커밋' 표)

---
</br>

# 🌐 외부 접속 (MetalLB VIP + Ingress)
> HTTP 서비스는 `MetalLB VIP` 하나로 모이고 `ingress-nginx` 가 **Host 헤더**로 갈라 보냅니다.
> 접속 주소는 `http://<호스트명>` — **포트가 붙지 않고**, 노드가 죽어도 MetalLB 가 VIP 를 옮겨 주소가 그대로입니다.

## 접속 방식

```text
브라우저 → VIP 192.168.56.240:80 → ingress-nginx (replica 2) → Host 헤더로 분기 → 각 Service
```

| 서비스 | 접속 주소 | 노출 방식 | 스택 (정본) |
|---|---|---|---|
| Harbor | http://data-layer-harbor | Ingress (차트가 생성 — 유일한 예외) | `200-harbor` (`harbor_host`) |
| Kafka UI | http://data-layer-kafka-ui | Ingress | `301-kafka` (`global.hosts.kafkaUi`) |
| Prometheus | http://data-layer-prometheus | Ingress | `302-monitoring` (`global.hosts.prometheus`) |
| Grafana | http://data-layer-grafana | Ingress | `302-monitoring` (`global.hosts.grafana`) |
| Airflow | http://data-layer-airflow | Ingress | `304-airflow` (`global.hosts.airflow`) |
| Data API | http://data-layer-api | Ingress (`proxy-body-size` 50m · `proxy-read-timeout` 300) | `305-api` (`global.hosts.api`) |
| PostgreSQL | 192.168.56.241:5432 | **전용 MetalLB VIP** (`-external` LoadBalancer, primary 를 따라간다) | `303-postgres` (`externalIp`, 풀은 `102-ingress`) |
| Kafka | 노드 IP:9092 | **hostNetwork** (브로커가 광고하는 주소 = 노드 IP, Service 없음) | `301-kafka` (`global.kafka.brokers`) |
| HDFS | 노드 IP:8020 / Web UI :9870 (ap·s1) | **hostNetwork** | `301-hadoop` (`global.hadoop`) |
| Elasticsearch | 노드 IP:9200 | **hostNetwork** (+ 내부 ClusterIP) | `301-elasticsearch` |
| MinIO / Neo4j / Spark / CDC 소스 RDB | 내부 전용 | ClusterIP → 사람은 `kubectl port-forward` | `301-minio` · `301-neo4j` · `308-spark` · `400-test-rdb` |

### 📌 규칙
- **Ingress 오브젝트는 각 앱 차트가 소유**하고 `ingressClassName: {{ .Values.global.ingressClassName }}`(nginx) 를 반드시 명시 → 빠뜨리면 조용히 404
- **경로가 아니라 호스트로 가른다** → 앱마다 base path 설정이 필요 없다
- **DB·Kafka·HDFS 같은 비-HTTP 는 Ingress 대상이 아니다** → Host 헤더가 없어 L7 을 못 탄다. NodePort 는 30000-32767 제약이라 표준 포트를 못 지켜 **VIP 또는 hostNetwork**
- **NodePort 를 되살리지 않는다** → 접속 경로가 둘로 갈라진다
- `externalTrafficPolicy: Local` 은 **인그레스 컨트롤러 Service 에만** → 클라이언트 IP 보존 + MetalLB L2 가 준비된 파드가 있는 노드에서만 VIP 광고
- 파드는 `data-layer-*` 이름을 못 푼다(CoreDNS 는 노드 `/etc/hosts` 를 안 본다) → 내부 호출은 ClusterIP DNS, 예외는 `305-api` 의 `hostAliases`(`global.ingressVip` 1줄 — Grafana 서버사이드 호출)

### 📌 변경 관리 (같은 커밋)
| 바꾸는 값 | 함께 가는 곳 |
|---|---|
| 호스트명 | `values.common.yaml` `global.hosts.*` · `200-harbor` `harbor_host` · Ansible `data_layer_vip_dns_names` · 접속 PC hosts |
| Ingress VIP | `102-ingress` `ingress_vip` · `values.common.yaml` `global.ingressVip` · Ansible `ingress_vip` |
| PostgreSQL VIP | `102-ingress` `postgres_vip` · `303-postgres` `externalIp` |
| 레지스트리 이름 | `global.harborRegistry`(`data-layer-harbor:80`) · 200 `harbor_host`/`externalURL` · Ansible `containerd_insecure_registries`/`buildkit_registry` · `build_and_push.sh` `REGISTRY` |

### ⚠️ 호스트명 작성 규칙 (RFC 1123)
- ✅ `data-layer-harbor`, `data-layer-api` → 영문/숫자/하이픈만
- ❌ `data_layer_harbor` → 밑줄은 DNS 라벨 불가. 레지스트리는 이미지 참조로 파싱조차 안 된다
- ❌ `data-layer-harbor.local` → `.local` 은 mDNS 예약 도메인(RFC 6762) → `systemd-resolved` 가 가로챈다
- 레지스트리 이름의 **`:80` 은 생략 불가** → 첫 마디에 `.`/`:` 이 없으면 Docker Hub 네임스페이스로 정규화된다

---
</br>

# 💾 쿠버네티스 스토리지 구성

> 기준: **누가 복제를 책임지는가?**
> - 앱이 스스로 복제 → 정적 Local PV 또는 `local-path`
> - 앱이 복제하지 못하는 단일 인스턴스 → `longhorn` (복제 2)

| StorageClass | 대상 | 이유 |
|---|---|---|
| `kafka-local` / `hadoop-local` / `elasticsearch-local` (정적 Local PV, no-provisioner, Retain) | `301-kafka` · `301-hadoop` · `301-elasticsearch` | hostNetwork + 노드에 박힌 인프라. 장애는 Kafka RF3 / HDFS 블록 복제 3 / ES replica 가 막는다. `claimRef` 로 PVC ↔ 노드가 고정된다 |
| `local-path` (**기본 StorageClass**) | `303-postgres` | 복제는 CNPG 스트리밍 리플리케이션(앱 레벨). longhorn 을 겹치면 2×2 = 4중 복제 |
| `local-path` | `200-harbor` PVC 5종 | 컴포넌트 전부 한 노드(`harbor_node_name`) 고정이라 이동할 일이 없다. 이미지 정본은 MinIO tar 백업 |
| `local-path` | `400-test-rdb` 4종 | 매일 `cdc_seed_loader` DAG 이 다시 채우는 테스트 데이터. Oracle 데이터파일 2중 복제는 디스크 낭비 |
| `longhorn` (복제 2) | `301-minio` · `301-neo4j` · `302-monitoring`(prometheus·grafana) | 자체 복제가 없는 단일 인스턴스 → 노드 장애 시 다른 노드에서 같은 볼륨을 붙여 재기동 |
| 없음 (hostPath 읽기 전용) | `304-airflow` · `308-spark` 코드 | 노드 로컬 디렉토리를 `304-airflow-rsync` 가 3노드에 맞춘다 |

## 📌 Longhorn 페일오버 조건 (`301-minio` · `301-neo4j` · `302`)
- `100-base` 의 `nodeDownPodDeletionPolicy: delete-both-statefulset-and-deployment-pod` → 죽은 노드의 파드를 강제 삭제 (지우면 파드가 `Terminating` 에 영원히 걸린다)
- 차트 values `tolerationSeconds`(60 — `301-minio` · `301-neo4j`) → 노드 장애 감지 후 퇴거 대기
- 옮겨 갈 노드에 Longhorn instance-manager 가 떠 있을 것 → 2 vCPU 노드는 CPU request 부족이면 **조용히** 안 뜬다
- Deployment 가 RWO PVC 를 쓰면 `strategy: Recreate` → RollingUpdate 는 Multi-Attach 로 죽는다
- 검증·판정·복구 절차 → `301-minio/RUNBOOK.md`

## ⚠️ 주의사항
- PVC 의 `storageClassName` 은 생성 후 변경 불가 → 스토리지 타입은 **최초 배포 전에 결정**
- `helm uninstall` 결과는 차트마다 다르다 → **README '주의' 를 먼저 읽는다**

| 결과 | 차트 |
|---|---|
| 네임스페이스째 삭제 (301~400 전부) | `300-data-layer-base` |
| PVC 삭제 = **데이터 소실** (longhorn reclaim Delete / CNPG Cluster CR 삭제) | `301-minio` · `301-neo4j` · `302-monitoring` · `303-postgres` |
| PVC 잔존 → **재설치 전에 PVC 삭제 필수** (pv-protection 이 Retain PV 를 붙잡는다 — 디스크 데이터는 그대로) | `301-kafka` · `301-hadoop` · `301-elasticsearch` |
| PVC 잔존 (초기화하려면 삭제) | `400-test-rdb` |
| 안전 (PVC 없음 — hook Job 은 남는다) | `304-airflow` · `304-airflow-rsync` · `305-api` · `306-cdc` · `307-pipeline` · `308-spark` |

---
</br>

# 📚 운영 노트

---

## 🔹 DAG/코드는 이미지에 없다 → hostPath + rsync (`304-airflow` · `304-airflow-rsync` · `308-spark`)

```bash
# DAG 수정 → 원본 노드(ap) 에서 편집하면 끝. 재빌드·helm upgrade 없음
vi /project/data_pipeline/data_layer_airflow/dags/collector_dag.py
#  → 304-airflow-rsync Sync Pod 가 inotify 로 감지 → debounce 5s → s1/s2 에 rsync
#  → dag-processor 가 30s 주기로 재스캔
#  → 30분 주기 전체 동기화가 놓친 이벤트·노드 복귀를 보완

# 수동 동기화가 필요할 때 (Ansible 저장소에서)
bin/start_airflow_repo_prereq.sh <Ansible 절대경로> sync

# 동기화 상태 → READY 0/1 이면 실패 노드가 있다
kubectl -n data-layer get pod -l app=airflow-rsync
```
- `304-airflow` 는 `repo.hostPath`(`/project/data_pipeline/data_layer_airflow`) 아래 `dags/collector/processor/publisher/utils` 를 `/opt/airflow/<이름>` 에 **읽기 전용** hostPath 로 마운트한다 (태스크 파드 원형 `airflow-pod-template` 도 동일)
- `308-spark` 는 같은 트리의 `spark_jobs` 를 `/opt/spark/jobs` 에 마운트 → 같은 rsync 가 맞춘다
- 이미지 재빌드 사유는 **`requirements.txt` 변경뿐** → 공용 `global.imageTag`
- 민감 정보는 이미지가 아니라 Secret `airflow-env`(`AIRFLOW__*` + `AIRFLOW_VAR_*`/`AIRFLOW_CONN_*`) → `cdc_*` Connection 만 UI 등록
- 태스크 로그는 `301-minio` 의 `airflow-logs` 버킷 (`global.minioBuckets.airflowLogs`, ILM 30일)
---

## 🔹 Airflow Task 는 Kubernetes 파드로 실행된다 (KubernetesExecutor)
- 태스크마다 파드가 생성되고, 성공하면 삭제된다
- 실패한 파드는 남긴다(`DELETE_WORKER_PODS_ON_FAILURE=False`) → `kubectl logs` 로 원인 확인 후 수동 정리
- 태스크 파드는 **실행된 노드의 hostPath** 를 읽는다 → 3노드 코드가 같아야 한다(위 rsync)
- 초기화 Job `airflow-init` 은 `post-install/upgrade` 훅 → 신규 설치 때 코어 4종이 잠시 `CrashLoopBackOff` 인 것이 정상. 그래서 **`--wait`/`--atomic` 금지, `--timeout 10m`**
---

## 🔹 노드 후보는 `nodeNames` + nodeAffinity 로 정한다 (nodeSelector 금지)

| 차트 | 값 | 현재 |
|---|---|---|
| `302-monitoring` | `prometheus.nodeNames` / `grafana.nodeNames` | s1 / s2 |
| `303-postgres` | `nodeNames` (+ required podAntiAffinity) | s1, s2 |
| `307-pipeline` | `tcpSocket.nodeNames` | s1 |
| `308-spark` | `nodeNames` (`jobs.hostPath` 가 후보 전부에 있어야 한다) | ap, s1, s2 |
| `304-airflow-rsync` | `source.nodeName` (원본·SSH 키가 hostPath) | ap |
| `301-kafka` · `301-hadoop` · `301-elasticsearch` | `global.kafka.brokers` / `global.hadoop.*.nodeNames` / `nodeNames` → **ordinal ↔ 노드** 를 정적 PV `claimRef` 가 고정 | 3노드 (NameNode 는 ap·s1) |

- `global.nodes` 에 없는 이름은 **렌더 단계에서 실패**한다 → 노드 라벨링 없이 값만 고친다
- 유일한 nodeSelector 예외는 `200-harbor`(`harbor_node_name` — PVC 5종이 local-path 라 어차피 고정)
- `tcp-socket-collector` 는 hostNetwork 라 **장비가 보내는 대상 IP = 파드가 뜬 노드 IP** → 후보를 둘 이상 주면 장비 쪽 대상 IP 가 전부를 커버해야 한다

```text
장비 → 192.168.56.39 (s1) → tcp-socket-collector (hostNetwork)
```

---

## 🔹 Node 장애가 발생해도 서비스 주소는 유지된다

```text
사용자
 ↓
VIP 192.168.56.240:80        ← MetalLB 가 살아 있는 노드로 옮긴다
 ↓
ingress-nginx (replica 2, required podAntiAffinity → 서로 다른 노드)
 ↓  Host 헤더로 분기
Service → Pod
```

- 전환 주체가 클라이언트가 아니라 **MetalLB** → 사용자는 주소를 바꾸지도 기다리지도 않는다
- `externalTrafficPolicy: Local` → 준비된 컨트롤러 파드가 있는 노드만 VIP 를 광고 → 죽은 컨트롤러로 흐르는 구간이 없다
- 노드 `/etc/hosts` 는 두 계열 → **VIP 계열**(harbor·kafka-ui·airflow·api·grafana·prometheus — 1줄, 전환 주체 MetalLB) + **노드 IP 계열**(`data-layer-neo4j` — 노드당 1줄, 전환 주체 클라이언트). 한 이름을 두 계열에 동시에 넣지 않는다
- 스토리지 계층의 장애 대응은 위 '스토리지 구성' → 노드에 박힌 인프라(Kafka/HDFS/ES)는 파드가 옮겨가지 **않고** 남은 복제본이 서비스를 잇는다, 단일 인스턴스(MinIO/Neo4j/Prometheus/Grafana)는 Longhorn 볼륨과 함께 옮겨간다

| | NodePort (이전) | VIP + Ingress (현재) |
|---|---|---|
| 접속 주소 | `이름:30300` | `이름` |
| 이름 → 주소 | 노드 IP 3개 | VIP 1개 |
| 장애 전환 주체 | 클라이언트 (TCP 타임아웃 대기) | MetalLB (수 초) |
| 서비스 추가 시 | 노드마다 포트 증가 | 열리는 포트 그대로 (80) |

---

## 🔹 설치 순서는 번호, 삭제는 역순

### 설치
```text
100-base
 ↓
101 → 102        ← 101(CRD) 이 apply 돼 있어야 102 의 plan 이 통과한다
 ↓
103              ← CNPG 오퍼레이터. 303 helm install 의 전제 (helm template 은 CRD 를 검증하지 않는다)
 ↓
200              ← 여기까지 플랫폼 (Terraform) → 이미지 빌드/push (0단계)
 ↓
300              ← 여기부터 Helm. 네임스페이스·공용 ConfigMap/Secret (-n default)
 ↓
301 (hadoop / kafka / minio / elasticsearch / neo4j — 서로 독립, 순서 무관)
 ↓
302 → 303 → 304 (airflow · airflow-rsync) → 305 → 306 → 307 → 308
 ↓
400              ← 테스트 픽스처. 마지막이며 건너뛰어도 300번대는 동작한다
```

> 사이의 수동 단계 → MinIO `config` 시드(301-minio 뒤) · Debezium 커넥터 등록 + Airflow `cdc_*` 커넥션(306/400 뒤)

### 삭제
```text
400 → 308 → 307 → 306 → 305 → 304 → 303 → 302 → 301
 ↓
300              ← helm uninstall data-layer-base -n default → 네임스페이스째 삭제. 반드시 301~400 이 먼저
 ↓
200 → 103
 ↓
102 → 101        ← 반드시 이 순서. MetalLB controller 가 살아 있어야 IPAddressPool 의 finalizer 가 풀린다
 ↓
100
```

- hook Job(`kafka-topics` · `hadoop-dirs` · `minio-buckets` · `airflow-init` · `cdc-mssql-init`)은 release manifest 가 아니라 `helm uninstall` 이 지우지 않는다 → `kubectl delete job` 을 함께
- 정적 Local PV 차트(kafka·hadoop·elasticsearch)는 재설치 전에 **PVC 를 먼저 삭제** → `Released` PV 는 `claimRef.uid` 만 patch 로 비운다

---
</br>

## 📌 운영 규칙
- **모든 버전은 정확 고정** → 업그레이드는 버전 변경 커밋으로만 (새 버전은 registry.terraform.io / 차트 index.yaml 에서 실존 확인 후)
- **`terraform apply/destroy` · `helm install/upgrade/uninstall` 은 엔지니어가 수행** → 자동화는 `plan` / `fmt` / `validate` / `helm lint` / `helm template` / `--dry-run=server` 까지
- **`data-layer` 네임스페이스를 `kubectl` 로 직접 수정하지 않는다** → Helm 3-way merge 가 다음 `upgrade` 에서 되돌리거나 충돌시킨다. 값 변경은 values/템플릿 → `helm upgrade`. 예외는 문서화된 수동 단계뿐(MinIO 시드, 커넥터/커넥션 등록, `--cascade=orphan` 재입양)
- **이미지 태그는 불변** → `imagePullPolicy: IfNotPresent` 라 재사용하면 롤아웃이 조용히 아무 일도 안 한다. `global.imageTag` 를 올릴 때는 이름 인자 없이 **26종 전부** push
- **접속 주소는 값이 아니라 파생값** → `KAFKA_BOOTSTRAP` · `COLLECTOR_DB_HOST` · `ICEBERG_WAREHOUSE` 등은 `_helpers.tpl` 이 `global` 원본(노드 표·clusterName·nameservice)에서 조립한다. 주소 문자열을 values 에 복사하지 않는다
- **설정 ConfigMap 은 그것을 읽는 워크로드 차트가 소유** → 같은 릴리스면 `checksum/*` 어노테이션으로 `helm upgrade` 만으로 롤아웃, 다른 릴리스(300 의 `data-layer-env` 를 읽는 306 등)면 **사람이 재기동**
- **OnDelete StatefulSet(kafka·hadoop)** 은 `helm upgrade` 로 재기동되지 않는다 → 사람이 한 대씩 (Kafka 는 URP 0 확인, NameNode 는 Standby → Active 순)
- **커밋** → `type(scope): subject`, 한국어 명령형 50자, scope 는 스택 번호 ([COMMIT_CONVENTION.md](COMMIT_CONVENTION.md)). Terraform apply 뒤 tfstate 변경분도 같은 흐름에서 커밋
