# ☸️ Terraform + Helm 기반 Kubernetes 배포 자동화 (IaC)

**Kubernetes 리소스를 코드로 선언하고,
`Data Pipeline Stack` 을 자동으로 배포/관리하기 위한 `IaC` 프로젝트 입니다.**

`Infrastructure as Code(IaC)` 기반으로 **클러스터 위의 애플리케이션을 코드로 관리하여 동일한 환경을 언제든 재현**할 수 있으며, **기능별로 구성 요소를 분리해 필요한 부분만 독립적으로 배포하고 관리할 수 있도록 표준화된 배포 체계를 제공**합니다.

플랫폼과 애플리케이션의 **변경 주기와 관리 목적이 다르기 때문에 도구를 분리**합니다.
- **Terraform → 플랫폼 기본 구성**  
- **Helm → 쿠버네티스 애플리케이션 배포**
- **ArgoCD → GitOps 기반 애플리케이션 지속 배포/상태 동기화**

---

## ✨ 도구를 나누는 기준

| 구간 | 대상 | 도구 | 목적 |
|---|---|---|---|
| `100 ~ 200` | Storage / LoadBalancer / Ingress / 커스텀 Operator / Harbor | **Terraform** | 플랫폼 기반을 구성하고 버전/설정을 고정 |
| `300 이후` | Data Pipeline 애플리케이션 | **Helm + ArgoCD** | 애플리케이션을 패키징하고 지속적으로 배포/업데이트 |

---

### 왜 이렇게 나누는가?

Storage, LoadBalancer, Ingress, Registry 같은 기반 구성은 애플리케이션보다 변경 빈도가 낮기 때문에 Terraform으로 **버전과 설정을 코드로 고정하고 `plan → apply` 방식으로 관리**합니다.

반면 **애플리케이션은 운영 과정에서 변경이 계속 발생합니다.**
기능 수정, 이미지 업데이트, 설정 변경, 스케일 조정, 버전 업그레이드, 롤백 및 재배포 등이 반복되기 때문에 애플리케이션을 **Helm Chart로 패키징**하여 변경에 유연하게 대응할 수 있도록 구성합니다.

향후 ArgoCD를 적용하면 Git에 반영된 Helm 변경 사항을 Kubernetes 클러스터에 자동으로 동기화하여 **GitOps 방식의 지속적인 배포 체계**로 확장할 수 있습니다.

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
├── 301-hadoop/             # HDFS HA (ZooKeeper, JournalNode, NameNode+ZKFC, DataNode) — Airflow 태스크 로그 저장소
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
- 모든 워크로드는 `data-layer-harbor:80/data-layer/<name>:<tag>` 를 pull 한다 (예외 없음 — `:80` 은 생략 불가, 포트 없는 단일 라벨은 docker.io 네임스페이스로 정규화된다)
- 여기서 쓴 태그를 `values.common.yaml` 의 `global.imageTag` 에 **그대로** 넣는다
  (예외: `303-postgres/values.yaml` 의 `imageTag` 는 `16.15-<tag>` 형식 — CNPG 가 태그에서 PG 버전을 읽는다. `build_and_push.sh 16.15-<tag> postgres` 로 따로 push)
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
  - Kubernetes에서 PostgreSQL의 **초기화·복제·Failover**를 자동 관리
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

## 2️⃣ 워크로드 → Helm 차트 (300 이후 ~)

```bash
# 테라폼/Helm 프로젝트 디렉토리 이동
cd /project/Infrastructure-as-Code-Terraform.kubernetes
```

---

### 🔹1. 300-data-layer-base
- **data-layer 워크로드 공용 오브젝트 프로비저닝**
  (`Namespace` 1 / `ConfigMap` 3 / `Secret` 2 / `ClusterRoleBinding` 1)

```bash
# 1. 300-data-layer-base 실행
#    global.* 은 차트에 없다 → values.common.yaml 을 반드시 같이 먹인다 (없으면 스키마가 렌더 전에 막음)
helm lint 300-data-layer-base -f values.common.yaml                          # 문법 + values.schema.json 검증
helm template data-layer-base 300-data-layer-base -f values.common.yaml      # 렌더 결과 미리 확인 (클러스터 접근 없음)

#    release 기록은 default 에 둔다 → data-layer 는 이 차트가 만들 대상이라 설치 시점엔 없다.
#    --create-namespace 는 금지 (차트의 Namespace 오브젝트와 "already exists" 충돌)
helm install data-layer-base ./300-data-layer-base -f values.common.yaml -n default


[검증]
# 1. 릴리스 상태
helm -n default ls                        → STATUS = deployed
helm -n default status data-layer-base    → STATUS = deployed

# 2. 네임스페이스 (차트가 소유)
kubectl get ns data-layer                 → STATUS = Active

# 3. 공용 ConfigMap / Secret
kubectl -n data-layer get cm/data-layer-env secret/data-layer-secrets        → DATA = 70 / 12
kubectl -n data-layer get cm,secret                                          → cm 3종 + secret 2종
                                                                             # (+ kube-root-ca.crt 는 K8s 가 자동 생성)

# 4. 설정 ConfigMap 2종 (301-kafka 가 볼륨 마운트로 소비)
kubectl -n data-layer get cm kafka-config kafka-jmx-exporter
#    alloy-config / prometheus-config 는 302-monitoring 소유다 (같은 릴리스여야 checksum 자동 롤아웃이 된다)

# 5. 파생 접속값이 실제 노드/서비스 주소와 맞는지 (values 가 아니라 _helpers.tpl 이 조립)
kubectl -n data-layer get cm data-layer-env -o jsonpath='{.data.KAFKA_BOOTSTRAP}'
  → 192.168.56.38:9092,192.168.56.39:9092,192.168.56.40:9092     # 노드 IP 직결 (hostNetwork)
kubectl -n data-layer get cm data-layer-env -o jsonpath='{.data.COLLECTOR_DB_HOST}'
  → data-layer-postgres-rw.data-layer.svc.cluster.local          # 303 CNPG rw Service

# 6. CNPG 전용 Secret (basic-auth → 303 이 role 생성에 사용)
kubectl -n data-layer get secret data-layer-postgres-app-user    → TYPE = kubernetes.io/basic-auth

# 7. 권한 바인딩
kubectl get clusterrolebinding data-layer-default-admin          → data-layer:default SA → cluster-admin
```

---

### 🔹2. 301-kafka
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

### 🔹3. 301-minio (s3)
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

### 🔹4. 301-hadoop
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


### 🔹5. 302-monitoring

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
helm install monitoring ./302-monitoring \
  -f values.common.yaml -n data-layer


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

### 🔹 6. 303-postgres

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

### 🔹 7. 304-airflow
- **Airflow 3.1.5** → KubernetesExecutor 기반
- **메타DB:** CNPG PostgreSQL
- **로그:** Hadoop HDFS(WebHDFS)
- **DAG/코드:** 각 노드의 hostPath 공유 구조

```bash
# =====================================================
# 0. 배포 전제
# =====================================================

# 필수 선행 스택
# - 300-data-layer-base : 공통 Secret/ConfigMap, 태스크 파드 생성 권한
# - 303-postgres        : Airflow 메타DB
# - 301-hadoop          : WebHDFS 로그 저장소
# - 301-minio           : DAG에서 사용하는 config 데이터

# DAG/코드는 모든 노드에 동일하게 배포
# → /data/airflow-repo/{dags,collector,processor,publisher,utils}
bin/start_airflow_repo_prereq.sh <ansible_dir> all

# HDFS 로그 디렉터리 준비
kubectl -n data-layer exec hadoop-namenode-0 -c namenode -- \
  hdfs dfs -mkdir -p /airflow-logs

kubectl -n data-layer exec hadoop-namenode-0 -c namenode -- \
  hdfs dfs -chown airflow:supergroup /airflow-logs

# Airflow 이미지가 Harbor에 있어야 함
./scripts/build_and_push.sh v0.1.0 airflow


# =====================================================
# 1. Helm 배포
# =====================================================

helm lint 304-airflow -f values.common.yaml
helm template airflow 304-airflow -f values.common.yaml

helm install airflow ./304-airflow \
  -f values.common.yaml \
  -n data-layer \
  --timeout 10m

# --timeout 10m : 초기 DB migration Job에 시간이 필요
# --wait / --atomic : 사용하지 않음
# 초기 CrashLoopBackOff : airflow-init 완료 전까지 정상


# =====================================================
# 2. 배포 상태 확인
# =====================================================

helm -n data-layer status airflow

kubectl -n data-layer get deploy,job,svc,ing \
  -l app.kubernetes.io/name=airflow

kubectl -n data-layer get pod \
  -l app.kubernetes.io/name=airflow -o wide

# 정상 상태
# - api-server       1/1
# - scheduler        1/1
# - dag-processor    1/1
# - triggerer        0/0 (랩 환경)
# - airflow-init     Completed

# 초기화 완료 확인
kubectl -n data-layer logs job/airflow-init | tail -5


# =====================================================
# 3. Airflow 정상 동작 확인
# =====================================================

# API / 전체 헬스
curl -s http://data-layer-airflow/api/v2/monitor/health

# Scheduler
kubectl -n data-layer exec deploy/airflow-scheduler -- \
  curl -s localhost:8974/health

# DAG 목록 / Import 오류 확인
kubectl -n data-layer exec deploy/airflow-dag-processor -- \
  airflow dags list

kubectl -n data-layer exec deploy/airflow-dag-processor -- \
  airflow dags list-import-errors

# Variable / Connection 확인
kubectl -n data-layer exec deploy/airflow-scheduler -- \
  airflow variables get collector_db_query

kubectl -n data-layer exec deploy/airflow-scheduler -- \
  airflow connections get collector_db


# =====================================================
# 4. DAG 실행 검증
# =====================================================

# DAG 활성화 후 실행
kubectl -n data-layer exec deploy/airflow-scheduler -- \
  airflow dags unpause Batch_Data_Collector

kubectl -n data-layer exec deploy/airflow-scheduler -- \
  airflow dags trigger Batch_Data_Collector

# KubernetesExecutor → 태스크마다 Worker Pod 생성
kubectl -n data-layer get pod \
  -l app.kubernetes.io/component=worker -w

# 실행 중 로그는 Worker Pod에서 확인
kubectl -n data-layer logs <worker-pod>


# =====================================================
# 5. HDFS 로그 확인
# =====================================================

# Worker 종료 후 HDFS에 로그 저장 여부 확인
curl -s \
  "http://192.168.56.39:9870/webhdfs/v1/airflow-logs?op=LISTSTATUS"

# → dag_id 기준 로그 디렉터리 생성 확인
# ※ Standby NN이면 Active NN 주소 사용


# =====================================================
# 6. DAG / 코드 반영
# =====================================================

# 코드 변경 → 이미지 재빌드 없이 전체 노드 동기화
bin/start_airflow_repo_prereq.sh <ansible_dir> sync

# 모든 노드의 /data/airflow-repo 가 동일해야 함
# requirements.txt 변경 시에만 이미지 재빌드


# =====================================================
# 7. 운영
# =====================================================

# values 변경 시 Helm Upgrade
helm upgrade airflow ./304-airflow \
  -f values.common.yaml \
  -n data-layer \
  --timeout 10m

# 실패한 Worker Pod 정리
kubectl -n data-layer delete pod \
  -l app.kubernetes.io/component=worker \
  --field-selector=status.phase=Failed

# Deferrable Operator 사용 시 triggerer replicas=1 이상 필요

# 삭제
helm uninstall airflow -n data-layer
kubectl -n data-layer delete job airflow-init
```

---

### 🔹 8. 305-api

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

### 🔹 9. 306-cdc

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

# ※ Debezium Plugin 스캔으로 첫 Ready까지 수 분 소요 가능
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


### 🔹 10. 307-pipeline

- **CDM 데이터 파이프라인 워커**
- Deployment **13개**
  - Mapper 8
  - Consumer 3
  - Lineage 1
  - TCP Collector 1
- PVC / Probe 없음
- TCP Collector는 **`ingest=true` 노드에서 hostNetwork로 실행**
- Mapper는 `cdm.mapper/module` 라벨을 사용 → 305-api의 DQ 제어 대상

```bash
# =====================================================
# 0. 수집 노드 지정
# =====================================================

# 실제 장비에서 패킷을 받을 노드에 라벨 지정
kubectl label node s2 ingest=true


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

### 🔹 11. 400-test-rdb

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




---


---
</br>

# 🧩 배포 전 필수 준비 사항

`Terraform`/`Helm` 을 실행하기 전에 아래 작업이 **먼저 완료되어야 합니다.**
준비되지 않은 상태에서 배포하면 일부 서비스가 정상적으로 실행되지 않습니다.

| 대상 | 먼저 해야 할 작업 |
|------|------------------|
| **~~** |  |

---
</br>

# 🏗️ Terraform 공통 설정 (versions.tf / providers.tf)

- 모든 스택은 동일한 `Terraform` 버전과 변수 관리 기준을 사용합니다.

## 1. Terraform / Provider

- `required_version = "1.15.8"` → Terraform CLI 버전 고정
- 버전 범위 연산자(`>=`, `~>`) 사용 금지
- **실제로 사용하는 Provider만 스택별로 선언**

| Provider | 사용 스택 | 용도 |
|---|---|---|
| `kubernetes 2.38.0` | `102`, `301~307`, `400` | Kubernetes 리소스 관리 |
| `helm 3.2.0` | `100`, `101`, `102`, `200` | Helm Chart 배포 |
| `harbor 3.10.21` | `200` | Harbor API 설정 |

> `100`, `101`, `200`은 `Helm Chart` 기반으로 구성하므로 `kubernetes` Provider를 사용하지 않습니다.

---

## 2. 변수 / `Secret` 관리

- 모든 변수는 **`variables.tf`에 `default`를 지정하지 않고 `terraform.tfvars`에서 명시적으로 관리**합니다.

| 파일 | 용도 |
|---|---|
| `variables.tf` | 변수 타입 및 필수값 정의 |
| `terraform.tfvars` | 환경별 실제 설정값 |
| `secrets.auto.tfvars` | 비밀번호, Token, API Key 등 Secret |
| `secrets.auto.tfvars.example` | Secret 작성 형식 제공 |

---

## 3. `terraform.tfvars`

- 환경에 따라 변경되는 **모든 일반 설정값을 정의**합니다.

```hcl
# Kubernetes / Node
node_ip = "192.168.0.x"

# Network
ingress_vip = "192.168.0.x"

# Registry
registry_host = "harbor.example.com"
image_tag     = "latest"

# Service
git_nodeport = 30000
```

> 실제 변수와 값은 각 환경에 맞게 작성하며, **값이 누락되면 `terraform plan` 단계에서 실패하도록 구성합니다.**

---

## 4. `secrets.auto.tfvars`

인증정보와 같은 민감한 값은 별도 파일로 분리합니다.

```hcl
harbor_password = "..."
api_key         = "..."
db_password     = "..."
```

- `.gitignore`에 등록
- `Git`에 `Secret`을 커밋하지 않음
- `secrets.auto.tfvars.example` 에는 **변수명과 형식만 제공**

---

## 5. 핵심 원칙
- `variables.tf` = 변수 정의
- `terraform.tfvars` = 변수 값
- `secrets.auto.tfvars` = 민감 정보
- `default` = 사용하지 않음

---
</br>

# 🌐 외부 접속 (MetalLB VIP + Ingress)
> HTTP 서비스는 `MetalLB VIP` 하나로 모이고, `Ingress`가 호스트명으로 갈라 보냅니다.
> 포트를 외울 필요가 없고, 노드 한 대가 죽어도 `MetalLB`가 VIP를 옮겨 주소가 그대로입니다.

## 접속 방식

```text
브라우저 → VIP 192.168.56.240:80 → ingress-nginx → (Host 헤더로 분기) → 각 Service
```

| 서비스 | 용도 | 접속 주소 | 노출 방식 | 스택 |
|---|---|---|---|---|
| Harbor | 컨테이너 이미지 저장소 | http://data-layer-harbor | Ingress | `200-harbor` |
| Kafka UI | Kafka 상태 확인 및 관리 | http://data-layer-kafka-ui | Ingress | `301-kafka` |
| Prometheus | 메트릭 수집/조회 | http://data-layer-prometheus | Ingress | `302-monitoring` |
| Grafana | 모니터링 대시보드 | http://data-layer-grafana | Ingress | `302-monitoring` |
| Airflow | 데이터 파이프라인 관리 | http://data-layer-airflow | Ingress | `304-airflow` |
| Data API | 데이터 레이어 API | http://data-layer-api | Ingress | `305-api` |
| PostgreSQL | 플랫폼 메타 DB (DBeaver 등 외부 도구) | 192.168.56.241:5432 | **전용 VIP (LoadBalancer)** | `303-postgres` (VIP 풀은 `102-ingress`) |


### 📌 변경 관리 규칙

- 호스트명을 변경할 경우 아래를 반드시 **같은 커밋**에서 함께 변경합니다.
  - 접속 정보 표 (이 표)
  - Terraform 각 스택 `variables.tf` 의 `<앱>_host`
  - Helm 차트 `300-data-layer-base/values.yaml` 의 `<앱>Host` 미러 (`kafkaUiHost` / `airflowHost` / `grafanaHost`)
  - Ansible `host.yml` 의 `data_layer_vip_dns_names`
- VIP를 변경할 경우 세 곳이 **글자 그대로** 같아야 합니다.
  - Terraform `102-ingress/terraform.tfvars` 의 `ingress_vip`
  - Terraform `305-api/terraform.tfvars` 의 `ingress_vip` (파드 hostAliases)
  - Ansible `host.yml` 의 `ingress_vip`

### ⚠️ 호스트명 작성 규칙
> Kubernetes DNS 규칙(RFC 1123)에 따라 호스트명은 아래 문자만 사용할 수 있습니다.

#### ✅ 허용
- data-layer-harbor
- data-layer-api

#### ❌ 잘못된 예
- data_layer_harbor
- `_`(밑줄)은 DNS 호스트명으로 사용할 수 없습니다.
- 이미지 주소나 서비스 주소로 사용할 경우 정상적으로 처리되지 않을 수 있습니다.

#### ⚠️ `.local` 사용 금지
- 예시: `data-layer-harbor.local`
- `.local`은 일반 DNS 이름이 아니라 PC 내부 네트워크 자동 검색(mDNS)에 예약된 도메인입니다.
- `Kubernetes` 서비스 접속 주소로 사용할 경우 운영체제가 `Kubernetes DNS` 대신 `mDNS`로 처리할 수 있어 환경별 접속 문제가 발생할 수 있습니다.

---
</br>

# 💾 쿠버네티스 스토리지 구성 (`local-path` vs `longhorn`)

> 기준: **앱 자체적으로 데이터를 복제하는가?**
>
- 복제가 가능한 데이터 → `local-path`
- 복제가 필요하지만 앱에서 처리하지 않는 데이터 → `longhorn`

| StorageClass | 대상 | 이유 |
|---|---|---|
| `local-path` | Harbor Trivy 캐시 | 삭제되어도 다시 생성 가능한 임시 데이터 |
| `local-path` | CDC 소스 RDB 4종 (`400-test-rdb`) | 테스트 데이터라 매일 01시 `cdc_seed_loader` DAG가 다시 채웁니다. 지켜야 할 원본이 없는데 Oracle 데이터파일(6.1G)을 2중 복제하면 랩 디스크만 소모합니다 |
| `local-path` | 플랫폼 PostgreSQL (`303-postgres`) | 복제를 CNPG 가 앱 레벨(스트리밍 리플리케이션 2인스턴스)에서 합니다. longhorn 을 겹치면 2 × 2 = 4중 복제가 됩니다 |
| `longhorn` | Harbor / Prometheus / Grafana | 노드 장애 시에도 데이터를 유지해야 하는 서비스 데이터 |

## 📌 Longhorn 적용 이유
- Harbor, Prometheus, Grafana는 자체 데이터 복제 기능이 없음
- 특정 노드 장애 시 다른 노드에서 볼륨을 연결해 복구할 수 있도록 Longhorn 사용
- 특히 **Harbor 장애는 전체 이미지 Pull 중단으로 이어질 수 있어 반드시 Longhorn 사용**

## ⚠️ 주의사항
- PVC 생성 후 `storageClassName` 변경 불가
- 변경하려면 PVC 삭제 및 재생성이 필요하며 기존 데이터가 사라질 수 있음
- 따라서 스토리지 타입은 **최초 배포 전에 결정**

---
</br>

# 📚 운영 노트

---

## 🔹 DAG는 airflow 이미지에 굽는다 (구 303-git + git-sync 퇴역)

```bash
# DAG 수정 후 반영 — 재빌드 → 태그 갱신 → apply
cd /my_project/data_pipeline
vi data_layer_airflow/dags/collector_dag.py

./scripts/build_and_push.sh v0.2.1 airflow
# 304-airflow/terraform.tfvars 의 image_tag 를 v0.2.1 로 수정
terraform -chdir=304-airflow apply
```
- DAG·커스텀 패키지는 airflow 이미지의 `/opt/airflow/repo` 에 있다 (선별 COPY 5종)
- 이미지 하나가 곧 코드 버전 — 파서(dag-processor)와 태스크 파드가 다른 커밋을 볼 방법이 없다
- 비밀번호, 키 같은 민감 정보는 이미지가 아니라 Kubernetes Secret(airflow-env)에서 관리한다
  (`airflow.env`·`scripts/airflow.conf` 는 COPY 대상에서 제외 — Dockerfile 주석 참조)
---

## 🔹 Airflow Task는 Kubernetes 파드로 실행된다 (KubernetesExecutor)
- `Airflow` 작업(`Task`)은 실행할 때마다 `Kubernetes` 파드로 생성된다
- 성공한 `Task` 파드는 삭제된다
- 실패한 `Task` 파드는 남겨서 `kubectl logs`로 장애 원인을 확인한다
---

## 🔹 실시간 수집기는 지정된 노드에 고정 배치한다

```bash
kubectl label node s2 ingest=true
kubectl get nodes -l ingest=true
```

- `tcp-socket-collector`는 외부 장비가 직접 접속하는 구조다
- 따라서 장비가 보내는 IP와 실제 파드 실행 위치가 같아야 한다

### 예시
```text
장비
 ↓
192.168.56.202 (s2)
 ↓
tcp-socket-collector
```

---

## 🔹 Node 장애가 발생해도 서비스 주소는 유지된다

- `MetalLB`가 VIP 하나를 노드 한 대에 붙여 두고, 그 노드가 죽으면 **살아 있는 노드로 옮긴다**
- 전환하는 주체가 클라이언트가 아니라 클러스터라, 사용자는 주소를 바꾸지도 기다리지도 않는다

### 구조
```text
사용자
 ↓
VIP 192.168.56.240:80        ← MetalLB가 살아 있는 노드로 옮겨 준다
 ↓
ingress-nginx (replica 2, 서로 다른 노드)
 ↓  Host 헤더로 분기
실제 Service → Pod
```

### 조건
- 인그레스 컨트롤러 Service만 `externalTrafficPolicy: Local`
  - MetalLB L2는 `Local`일 때 **준비된 파드가 있는 노드에서만** VIP를 광고한다
  - 덕분에 죽은 컨트롤러 쪽으로 트래픽이 흘러가는 구간이 없다
- 컨트롤러는 `replica 2` + `podAntiAffinity`로 서로 다른 노드에 배치
  - 한 노드에 뭉치면 그 노드가 죽는 순간 VIP를 광고할 노드가 사라진다

### 이전 방식(NodePort)과의 차이
| | NodePort (이전) | VIP + Ingress (현재) |
|---|---|---|
| 접속 주소 | `이름:30300` — 포트 암기 필요 | `이름` — 포트 없음 |
| 이름 → 주소 | 이름 하나가 노드 IP 3개 | 이름 전부가 VIP 1개 |
| 장애 전환 주체 | **클라이언트** (죽은 IP로 먼저 붙으면 TCP 타임아웃 대기) | **MetalLB** (수 초 내 VIP 이동) |
| 서비스 추가 시 | 노드마다 포트가 하나씩 늘어남 | 열리는 포트는 그대로(80) |

```text
이전(NodePort)

사용자
  |
NodeIP:30001 → Service A
NodeIP:30002 → Service B
NodeIP:30003 → Service C

------------------------------

현재(MetalLB + Ingress)

사용자
  |
VIP (고정 IP)
  |
Ingress
  |
  ├── Service A
  ├── Service B
  └── Service C
```

---

## 🔹 Kubernetes 리소스 삭제 순서는 역순이다

### 설치
```text
100-base
 ↓
101 → 102        ← 101(CRD) 이 있어야 102 의 plan 이 통과한다
 ↓
200              ← 여기까지 플랫폼 (Terraform)
 ↓
300              ← 여기부터 워크로드 — 300 은 Helm 차트 (helm install)
 ↓
301 ~ 307
 ↓
400              ← 테스트 픽스처. 마지막이며 건너뛰어도 300번대는 동작한다
```

### 삭제
```text
400        ← 테스트 픽스처라 의존하는 스택이 없다. 맨 먼저 지워도 된다
 ↓
307
 ↓
306
 ↓
...
301
 ↓
300
 ↓
200
 ↓
102 → 101        ← 반드시 이 순서. MetalLB controller 가 살아 있어야
 ↓                  IPAddressPool 의 finalizer 가 풀린다
100
```

> `300-data-layer-base` 는 Helm 스택입니다 — 삭제는 `helm uninstall data-layer-base -n default`.
> ⚠ uninstall 은 `data-layer` **네임스페이스째 삭제**하므로, 반드시 `301~400` 을 먼저 지운 뒤 실행합니다.

---


</br>

## 📌 운영 규칙
- **모든 버전은 고정 관리**
  - 업그레이드는 버전 변경 커밋으로만 진행
- **terraform apply / destroy · helm install / upgrade / uninstall 은 엔지니어가 수행**
- **`kubectl` 직접 수정 금지**
  - `Terraform`(Server-Side Apply 필드 소유권) / `Helm`(릴리스 매니페스트) 과의 충돌 방지

---