# ☸️ Terraform + Helm(ArgoCD) 기반 Kubernetes 배포 자동화 (IaC)

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
├── 301-kafka-tools/        # Kafka 및 운영 도구 (Kafka, Schema Registry, UI, Exporter)
├── 302-monitoring/         # 모니터링 스택 (Alloy, Prometheus, Grafana)
├── 303-postgres/           # PostgreSQL 클러스터 구성 (CNPG, 3인스턴스)
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
docker login data-layer-harbor              # 사전: /etc/docker/daemon.json 의 insecure-registries
/my_project/data_pipeline/scripts/build_and_push.sh v0.1.0
```
- 모든 워크로드는 `data-layer-harbor/data-layer/<name>:<tag>` 를 pull 한다 (예외 없음)
- 여기서 쓴 태그를 각 스택 `terraform.tfvars` 의 `image_tag` 에 **그대로** 넣는다
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
- **data-layer 워크로드 공용 오브젝트 프로비저닝(`Namespace`, `ConfigMap`, `Secret`, `ClusterRoleBinding`)**

```bash
1. 300-data-layer-base 실행
helm lint 300-data-layer-base                         → 문법 + values.schema.json 검증
helm template data-layer-base 300-data-layer-base     → 렌더 결과 미리 확인 (클러스터 접근 없음)
helm install data-layer-base ./300-data-layer-base -n default   → 공용 오브젝트 4종 생성


[검증]
1. 릴리스 상태 확인
helm -n default ls                        → STATUS = deployed
helm -n default status data-layer-base    → STATUS = deployed

2. 네임스페이스 생성 확인
kubectl get ns data-layer → STATUS = Active

3. 공용 ConfigMap / Secret 확인
kubectl -n data-layer get cm/data-layer-env secret/data-layer-secrets → DATA = 70 / 12

4. 클러스터 밖 접속값이 실제 노드 주소와 맞는지
kubectl -n data-layer get cm data-layer-env -o jsonpath='{.data.KAFKA_BOOTSTRAP}' → 192.168.0.38:9092,192.168.0.39:9092,192.168.0.40:9092

5. 권한 바인딩 확인
kubectl get clusterrolebinding data-layer-default-admin → default SA 에 cluster-admin
```

---
</br>

# 🧩 배포 전 필수 준비 사항

`Terraform`/`Helm` 을 실행하기 전에 아래 작업이 **먼저 완료되어야 합니다.**
준비되지 않은 상태에서 배포하면 일부 서비스가 정상적으로 실행되지 않습니다.

| 대상 | 먼저 해야 할 작업 | 준비되지 않으면 |
|------|------------------|----------------|
| **~~** |  |  |


---
</br>

# 🏗️ Terraform 공통 설정 (versions.tf / providers.tf)

모든 스택은 동일한 Terraform 버전과 변수 관리 기준을 사용합니다.

## 1. Terraform / Provider

- `required_version = "1.15.8"` → Terraform CLI 버전 고정
- 버전 범위 연산자(`>=`, `~>`) 사용 금지
- **실제로 사용하는 Provider만 스택별로 선언**

| Provider | 사용 스택 | 용도 |
|---|---|---|
| `kubernetes 2.38.0` | `102`, `301~307`, `400` | Kubernetes 리소스 관리 |
| `helm 3.2.0` | `100`, `101`, `102`, `200` | Helm Chart 배포 |
| `harbor 3.10.21` | `200` | Harbor API 설정 |

> `100`, `101`, `200`은 Helm Chart 기반으로 구성하므로 `kubernetes` Provider를 사용하지 않습니다.

---

## 2. 변수 / Secret 관리

모든 변수는 **`variables.tf`에 `default`를 지정하지 않고 `terraform.tfvars`에서 명시적으로 관리**합니다.

| 파일 | 용도 |
|---|---|
| `variables.tf` | 변수 타입 및 필수값 정의 |
| `terraform.tfvars` | 환경별 실제 설정값 |
| `secrets.auto.tfvars` | 비밀번호, Token, API Key 등 Secret |
| `secrets.auto.tfvars.example` | Secret 작성 형식 제공 |

---

## 3. `terraform.tfvars`

환경에 따라 변경되는 **모든 일반 설정값을 정의**합니다.

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
- `terraform.tfvars` = 환경 설정값
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
| Kafka UI | Kafka 상태 확인 및 관리 | http://data-layer-kafka-ui | Ingress | `301-kafka-tools` |
| Prometheus | 메트릭 수집/조회 | http://data-layer-prometheus | Ingress | `302-monitoring` |
| Grafana | 모니터링 대시보드 | http://data-layer-grafana | Ingress | `302-monitoring` |
| Airflow | 데이터 파이프라인 관리 | http://data-layer-airflow | Ingress | `304-airflow` |
| Data API | 데이터 레이어 API | http://data-layer-api | Ingress | `305-api` |
| PostgreSQL | 플랫폼 메타 DB (DBeaver 등 외부 도구) | 192.168.56.241:5432 | **전용 VIP (LoadBalancer)** | `303-postgres` (VIP 풀은 `102-ingress`) |

### ⚠️ PostgreSQL 만 전용 VIP 를 씁니다 (NodePort 는 이제 없습니다)

DB 프로토콜은 HTTP 가 아니라 **Host 헤더가 없어** 인그레스(L7)를 못 탑니다. NodePort 는 30000-32767 제약 때문에 표준 포트 5432 를 지킬 수 없어, MetalLB VIP 하나(`postgres-vip` 풀)를 따로 받아 `:5432` 그대로 엽니다. 장애 전환은 인그레스 VIP 와 같은 원리로 MetalLB 가 합니다. (구 303-git 의 NodePort 30418 은 스택 퇴역과 함께 사라져 **NodePort 는 더 이상 없습니다.**)

### 📌 위 표에 테스트 DB가 없는 이유

`400-test-rdb`의 소스 DB 4종은 **외부에 열지 않습니다.** 접속하는 쪽(Kafka Connect·Airflow)이 전부 클러스터 안이라 Service 이름으로 충분합니다. 사람이 DB 클라이언트로 볼 때만 `kubectl port-forward`를 씁니다 → [400-test-rdb 스택](#-cdc-소스-rdb-스택-400-test-rdb--테스트-픽스처)

### ⚠️ Harbor는 주소가 아니라 "이미지 이름"입니다

```
data-layer-harbor/data-layer/kafka-ui:v0.1.0
└───────┬───────┘
   레지스트리 = 이미지 이름의 첫 마디
```

노드의 containerd는 이 앞마디와 **글자 그대로 같은** 폴더를 찾아 접속 규칙을 읽습니다.

```
/etc/containerd/certs.d/data-layer-harbor/hosts.toml
                        └─── 이름이 곧 폴더명 ───┘
```

못 찾으면 기본값인 HTTPS로 붙어 `server gave HTTP response to HTTPS client`로 실패합니다.
그래서 이 이름을 바꾸려면 **같은 커밋에서 5곳**이 함께 가야 합니다 — `harbor_host` / 전 스택 `harbor_registry` / `externalURL` / harbor 프로바이더 URL / Ansible `containerd_insecure_registries`.

> **인그레스 뒤에서는 IP로 우회 pull이 불가능합니다.** 인그레스는 Host 헤더로 목적지를 고르는데, IP로 치면 헤더가 IP라서 어떤 규칙에도 걸리지 않고 404가 됩니다. 이름 해석이 의심되면 `/etc/hosts`와 VIP의 ARP 응답을 먼저 확인하세요.

### 📌 변경 관리 규칙

- 호스트명을 변경할 경우 아래를 반드시 **같은 커밋**에서 함께 변경합니다.
  - 접속 정보 표 (이 표)
  - Terraform 각 스택 `variables.tf` 의 `<앱>_host`
  - Helm 차트 `300-data-layer-base/values.yaml` 의 `<앱>Host` 미러 (`kafkaUiHost` · `airflowHost` · `grafanaHost`)
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

# 💾 스토리지 구성 (local-path vs longhorn)

> 기준: **앱 자체적으로 데이터를 복제하는가?**
>
- 복제가 가능한 데이터 → `local-path`
- 복제가 필요하지만 앱에서 처리하지 않는 데이터 → `longhorn`

| StorageClass | 대상 | 이유 |
|---|---|---|
| `local-path` | Harbor Trivy 캐시 | 삭제되어도 다시 생성 가능한 임시 데이터 |
| `local-path` | CDC 소스 RDB 4종 (`400-test-rdb`) | 테스트 데이터라 매일 01시 `cdc_seed_loader` DAG가 다시 채웁니다. 지켜야 할 원본이 없는데 Oracle 데이터파일(6.1G)을 2중 복제하면 랩 디스크만 소모합니다 |
| `local-path` | 플랫폼 PostgreSQL (`303-postgres`) | 복제를 CNPG 가 앱 레벨(스트리밍 리플리케이션 3인스턴스)에서 합니다. longhorn 을 겹치면 3 × 2 = 6중 복제가 됩니다 |
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