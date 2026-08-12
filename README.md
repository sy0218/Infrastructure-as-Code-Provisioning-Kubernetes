# ☸️ Terraform + Helm(ArgoCD) 기반 쿠버네티스 배포 자동화 (IaC)

**쿠버네티스 리소스를 코드로 선언하고,
데이터 파이프라인 스택을 자동으로 배포하는 프로젝트 입니다.**

Infrastructure as Code(IaC) 기반으로 **클러스터 위의 애플리케이션을 코드로 관리하여 동일한 환경을 언제든 재현**할 수 있으며, **기능별로 구성 요소를 분리해 필요한 부분만 독립적으로 배포하고 관리할 수 있도록 표준화된 배포 체계를 제공**합니다.

**역할에 따라 도구를 나눠 씁니다** — 플랫폼(`100~200`)은 **Terraform**, 애플리케이션 워크로드(`300` 이후)는 **Helm 차트(+ ArgoCD 예정)** 로 배포합니다. 이유는 [도구 경계](#-도구-경계--terraform과-helm을-나눠-쓰는-이유) 참조.

---
</br>

# ✨ 주요 특징
- **역할별 도구 분리** → 플랫폼(100~200)은 Terraform, 애플리케이션 워크로드(300 이후)는 Helm 차트(+ ArgoCD)
- **스택 기반 모듈 구조** → 번호 디렉토리 하나 = 독립 스택(Terraform 루트 모듈 또는 Helm 차트), 번호가 곧 적용 순서
- **매니페스트 템플릿화** → Terraform 은 `kubernetes_manifest` + `templatefile`, Helm 은 `templates/` + `values.schema.json` 으로 YAML 을 변수에서 조립

---
</br>

# 🧭 도구 경계 — Terraform과 Helm을 나눠 쓰는 이유

> **한 줄 요약: 남이 만든 것(플랫폼)은 Terraform 으로 설치하고, 우리가 만든 것(워크로드)은 Helm 차트로 배포합니다.**

| 구간 | 내용물 | 도구 | 이유 |
|---|---|---|---|
| `100 ~ 103` | 스토리지 · LoadBalancer · Ingress · DB 오퍼레이터 | **Terraform** | 서드파티 차트 설치 + CR 적용 순서 제어(`depends_on`) |
| `200` | Harbor 레지스트리 | **Terraform** | 차트 설치 + **Harbor REST API 설정**(프로젝트 생성)은 차트로 표현 불가 |
| `300 이후` | 데이터 파이프라인 워크로드 | **Helm 차트 (+ ArgoCD 예정)** | 직접 작성한 매니페스트라 자기 차트가 됨 · sync-wave 가 번호 순서를 대체 |

## 왜 이렇게 나누는가

- **100~200 의 내용물은 이미 Helm 입니다.** 전부 `helm_release` 로 서드파티 차트(local-path · Longhorn · MetalLB · ingress-nginx · Harbor)를 설치하는 스택입니다. 이걸 다시 Helm 차트로 감싸면 업스트림 차트에 values 만 넘기는 빈 껍데기 차트가 생길 뿐이고, 대신 `terraform plan` 의 변경 미리보기와 버전 고정 강제를 잃습니다.
- **200-harbor 는 순수 Helm 으로 표현할 수 없습니다.** `harbor_project` 리소스가 Harbor **REST API** 를 호출해 `data-layer` 프로젝트를 만듭니다 — 쿠버네티스 오브젝트가 아니라서 차트 템플릿으로 만들 수 없습니다.
- **102 의 설치 순서는 Terraform 이 해결합니다.** ingress-nginx 는 MetalLB `IPAddressPool` 이 먼저 있어야 EXTERNAL-IP 를 받습니다. Helm 에는 릴리스 간 `depends_on` 이 없습니다.
- **300 이후는 직접 작성한 워크로드입니다.** 차트로 만들면 진짜 자기 차트(`templates/` + `values.schema.json`)가 나오고, 그대로 ArgoCD Application 이 됩니다.

## 전환 로드맵 (현재 위치)

| 단계 | 내용 | 상태 |
|---|---|---|
| 1 | `300-data-layer-base` 를 Terraform → Helm 차트로 전환 | ✅ 완료 (첫 전환 스택) |
| 2 | `301~307` · `400` 을 Helm 차트로 전환 | 🔄 진행 중 (301 · 302 완료) |
| 2.5 | PostgreSQL 을 노드 로컬(Ansible) → K8s 복귀 — `103-cnpg`(오퍼레이터) + `303-postgres`(CNPG Cluster, 구 303-git 자리) | ✅ 완료 (컷오버는 배포 순서 참조) |
| 3 | ArgoCD 설치 — Terraform 신규 스택(예: `201-argocd`)으로 부트스트랩 | 📋 계획 |
| 4 | app-of-apps 구성 — **sync-wave 가 디렉토리 번호 순서를 대체** | 📋 계획 |

> 전환이 끝나면 Terraform 의 역할은 **"클러스터 위 플랫폼 부트스트랩(100~201)"** 으로 닫히고,
> 이후의 모든 워크로드 변경은 **`git push → ArgoCD sync`** 로만 흐릅니다.

---
</br>

# 📋 프로젝트 환경
| 항목 | 내용 |
|------|------|
| Kubernetes | kubeadm 3노드 (ap=.200 control-plane / s1=.201 / s2=.202), `v1.34.4`, containerd |
| Terraform | `1.15.8` — 플랫폼(100~200) + Helm 전환 전 워크로드 스택 |
| Helm | `3.19.0` — 워크로드 차트(300 이후) 배포용 CLI |
| Provider | kubernetes `2.38.0` / helm `3.2.0` / harbor `3.10.21` |
| Helm 차트 | local-path `0.0.37` / longhorn `1.11.3` / metallb `0.16.1` / ingress-nginx `4.15.1` / harbor `1.18.4` / cloudnative-pg `0.29.0` |
| Cluster Access | ~/.kube/config (cluster-admin) |
| 선행 조건 (Ansible) | Kubernetes / Longhorn Prerequisites / etc_hosts / Kafka / MinIO / Neo4j (PostgreSQL 롤은 퇴역 — `303-postgres` 가 승계) |
| 선행 조건 (Manual) | 이미지 21종 Build & Push (`build_and_push.sh`) |

---
</br>

# 📂 디렉토리 구조
```bash
Infrastructure-as-Code-Terraform.kubernetes/
│
│ # ── 플랫폼 (Terraform) ─────────────────────────────────────────
├── 100-base/               # Kubernetes 기본 환경 구성 (StorageClass, Longhorn)
├── 101-metallb/            # MetalLB (온프렘 LoadBalancer — 차트만, VIP는 102 소유)
├── 102-ingress/            # 외부 접속 진입점 (VIP + ingress-nginx) + PostgreSQL 외부 VIP
├── 103-cnpg/               # CloudNativePG 오퍼레이터 (Cluster CR 은 303 소유)
├── 200-harbor/             # Harbor 이미지 레지스트리
│
│ # ── 애플리케이션 워크로드 (Helm 차트 + ArgoCD 예정 · ✅ = 전환 완료) ──
├── 300-data-layer-base/    # ✅ 데이터 레이어 공통 리소스 (Namespace, ConfigMap, Secret, RBAC)
├── 301-kafka-tools/        # ✅ Kafka 운영 도구 (Schema Registry, Kafka UI, Exporter)
├── 302-monitoring/         # ✅ 모니터링 (Alloy, Prometheus, Grafana)
├── 303-postgres/           # ✅ 플랫폼 PostgreSQL (CNPG Cluster 3인스턴스 — 구 303-git 자리)
├── 304-airflow/            # Airflow 워크플로우 엔진
├── 305-api/                # Data Layer API 및 관리 화면
├── 306-cdc/                # CDC(Kafka Connect + Debezium)
├── 307-pipeline/           # 데이터 처리 파이프라인 및 Consumer
└── 400-test-rdb/           # CDC 소스 RDB 4종 (테스트 픽스처 — Oracle/SQL Server/PostgreSQL/MySQL)
```

## 각 디렉토리의 의미
- **하나의 번호 디렉토리 = 하나의 서비스(스택)** — 독립적으로 배포/삭제할 수 있습니다.
- **Terraform 스택**(100~200, 301~400 중 전환 전 스택)은 자신만의 Terraform State 를 가지며, 다른 스택과 State 를 공유하지 않습니다.
- **Helm 차트 스택**(현재 `300-data-layer-base` · `301-kafka-tools` · `302-monitoring` · `303-postgres`)은 자신만의 Helm 릴리스로 관리됩니다.
- 스택 간 실행 순서는 **디렉토리 번호(100 → 200 → 300 …)** 로 관리합니다.
  - ArgoCD 도입 후에는 이 번호 순서를 **sync-wave** 가 대체할 예정입니다.

> 즉, **100-base**를 먼저 배포한 후 **200-harbor**, 이후 **300-data-layer-base** 순으로 배포하면 됩니다.

---

## Terraform 스택의 공통 파일 구성 (100~200 · 301~400 중 전환 전 스택)

```bash
각 스택 내부(공통 파일 구성):
├── versions.tf             # Terraform 및 Provider 버전 고정
├── providers.tf            # Kubernetes Provider 설정
├── variables.tf            # 입력 변수 정의
├── terraform.tfvars        # 환경별 설정값
├── secrets.auto.tfvars     # 비밀번호 등 민감 정보 (Git 제외)
├── outputs.tf              # 다른 스택에서 사용할 출력값
├── <컴포넌트>.tf           # 컴포넌트별 Terraform 리소스
├── manifests/*.yaml.tftpl  # Kubernetes YAML 템플릿
└── manifests/*.sql.tftpl   # DB 초기화 스크립트 템플릿 (400-test-rdb 만 사용)
```
> **번호 디렉토리 하나가 독립된 Terraform 루트 모듈이며 각자 자기 state를 가집니다. 스택 간 의존성은 코드가 아니라 번호 순서가 담당합니다.**

### 파일 역할

| 파일 | 역할 |
|------|------|
| `versions.tf` | Terraform과 Provider 버전을 고정합니다. |
| `providers.tf` | Kubernetes 클러스터 연결 정보를 설정합니다. |
| `variables.tf` | 사용되는 변수들을 정의합니다. |
| `terraform.tfvars` | 환경별 설정값을 입력합니다. |
| `secrets.auto.tfvars` | 비밀번호, 토큰 등 민감 정보를 관리합니다. (Git 커밋 금지) |
| `outputs.tf` | 다른 스택이나 운영자가 사용할 값을 제공합니다. |
| `*.tf` | 서비스별 리소스를 정의합니다. (`main.tf` 대신 기능별 파일로 분리) |
| `manifests/*.yaml.tftpl` | Terraform이 사용할 Kubernetes YAML 템플릿입니다. |
| `manifests/*.sql.tftpl` | DB 초기화 SQL 템플릿입니다. ConfigMap으로 만들어져 컨테이너에 마운트됩니다. (`400-test-rdb`) |

> **설계 원칙**
>
> - **1개의 번호 디렉토리 = 1개의 독립적인 Terraform 프로젝트**
> - **1개의 `.tf` 파일 = 1개의 기능(컴포넌트)**
> - **1개의 `.yaml.tftpl` = 1개의 Kubernetes 리소스(YAML 문서)**
> - 스택 간 의존성은 Terraform 코드가 아닌 **배포 순서(디렉토리 번호)** 로 관리합니다.

---

## Helm 차트 스택의 공통 파일 구성 (300 이후 · 전환 완료 스택)

```bash
각 차트 내부(공통 파일 구성):
├── Chart.yaml              # 차트 이름/버전 (정확 고정 — 범위 금지)
├── values.yaml             # 환경별 설정값
├── values.schema.json      # 필수 키/형식 검증 (누락·오타를 배포 전에 차단)
├── templates/*.yaml        # Kubernetes YAML 템플릿
└── templates/NOTES.txt     # 설치 후 안내 출력
```

### Terraform ↔ Helm 대응 관계
> 두 형식은 **같은 원칙을 다른 문법으로 구현**합니다. Terraform 스택만 보던 사람도 아래 표만 알면 차트를 읽을 수 있습니다.

| Terraform | Helm | 역할 |
|---|---|---|
| `terraform.tfvars` | `values.yaml` | 환경별 설정값 |
| 변수에 `default` 없음 → `plan` 에러 | `values.schema.json` 의 `required` | 필수값 누락을 배포 전에 차단 |
| `manifests/*.yaml.tftpl` | `templates/*.yaml` | Kubernetes YAML 템플릿 |
| `terraform plan` | `helm template` + `kubectl diff` | 배포 전 변경 미리보기 |
| Terraform State | Helm 릴리스 기록 (`sh.helm.release.v1.*` Secret) | 배포 이력/소유 추적 |

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
- `300-data-layer-base` 는 이미지를 쓰지 않아(`harbor_registry`/`image_tag` 값 없음) 이 단계보다 먼저 배포해도 된다

---
</br>

# 🚀 배포 실행
**번호 순서대로** 배포합니다. 플랫폼(100~200)은 Terraform, 워크로드(300 이후)는 Helm 입니다.

## 1) 플랫폼 — Terraform (100 ~ 200)
스택마다 각자 `init` 부터 시작합니다.
```bash
terraform -chdir=100-base init && terraform -chdir=100-base apply

terraform -chdir=101-metallb init && terraform -chdir=101-metallb apply
# ↑ 101 을 apply 해야 102 의 plan 이 통과합니다 (MetalLB CRD 가 여기서 생깁니다)
terraform -chdir=102-ingress init && terraform -chdir=102-ingress apply
# ↑ 인그레스 VIP(.240)와 함께 PostgreSQL 외부 접속 VIP(.241, postgres-vip 풀)도 여기서 등록됩니다

terraform -chdir=103-cnpg init && terraform -chdir=103-cnpg apply
# ↑ CloudNativePG 오퍼레이터(CRD 포함)만 설치합니다 — Cluster CR 은 303-postgres 차트 소유.
#   103 을 apply 해야 303 의 helm install 이 통과합니다 ("no matches for kind Cluster" 방지)

terraform -chdir=200-harbor init && terraform -chdir=200-harbor apply
# ↑ 여기서 build_and_push.sh 실행

# [이미 NodePort 로 떠 있는 Harbor 를 인그레스로 바꾸는 '전환' 상황에만 해당]
#   harbor 프로바이더 URL 이 이미 새 주소(http://data-layer-harbor)인데 그 경로를 여는
#   Ingress 는 아직 없어서, 평소처럼 apply 하면 refresh 단계에서
#   "dial tcp ...:80: connect: connection refused" 로 죽는다.
#   refresh 를 한 번 건너뛰어 Ingress 를 먼저 만든 뒤, 그 다음부터 정상 apply 한다.
#   terraform -chdir=200-harbor apply -refresh=false
#   terraform -chdir=200-harbor apply
```

## 2) 워크로드 — Helm (300 이후)
```bash
# 공통 리소스 (Namespace/ConfigMap/Secret/RBAC) — 첫 Helm 전환 스택
helm template data-layer-base ./300-data-layer-base        # 배포 전 미리보기
helm install data-layer-base ./300-data-layer-base -n default
# ↑ 릴리스 기록은 default 네임스페이스에 둡니다 — data-layer 네임스페이스는 차트 자신이 만듭니다
#   (--create-namespace 금지: 차트의 Namespace 오브젝트와 소유권이 충돌합니다)
#   값 변경은 helm upgrade 로만 합니다 — uninstall 은 네임스페이스째 지워 301~400 의 모든 워크로드가 같이 사라집니다

# 301 은 Helm 전환 완료 — Kafka 운영 도구
helm template kafka-tools ./301-kafka-tools                # 배포 전 미리보기
helm install kafka-tools ./301-kafka-tools -n data-layer

# 302 는 Helm 전환 완료 — 모니터링 (Alloy/Prometheus/Grafana)
helm template monitoring ./302-monitoring                  # 배포 전 미리보기
helm install monitoring ./302-monitoring -n data-layer
# ↑ 릴리스 기록은 data-layer 에 둡니다 — 300 과 달리 네임스페이스가 이미 있습니다

# 303 은 Helm 전환 완료 — 플랫폼 PostgreSQL (CNPG Cluster 3인스턴스)
helm lint 303-postgres                                     # 문법 + 스키마 검사
helm template postgres ./303-postgres                      # 미리보기 (⚠ CRD 검증은 안 됩니다 — 103 필요)
helm install postgres ./303-postgres -n data-layer
kubectl -n data-layer get cluster data-layer-postgres      # "Cluster in healthy state" 확인 후 304 진행

terraform -chdir=304-airflow init && terraform -chdir=304-airflow apply
# ↑ 303 의 CNPG 클러스터가 healthy 여야 init Job(db migrate)이 통과합니다
terraform -chdir=305-api init && terraform -chdir=305-api apply
terraform -chdir=306-cdc init && terraform -chdir=306-cdc apply
terraform -chdir=307-pipeline init && terraform -chdir=307-pipeline apply

terraform -chdir=400-test-rdb init && terraform -chdir=400-test-rdb apply
# ↑ CDC 소스 RDB 4종. 파이프라인의 일부가 아니라 그 입력을 흉내 내는 테스트 픽스처라
#   맨 뒤이고, 여기까지 오면 s1 의 docker 를 제거할 수 있습니다.
#   ⚠ 넷을 한꺼번에 올리면 랩 용량(노드당 2.8Gi)을 넘깁니다 — 아래 '필수 준비 사항' 참조.
```
> `[주의]` **`terraform apply/destroy` · `helm install/upgrade/uninstall` 은 엔지니어가 직접 실행합니다.**
>
> ArgoCD 도입 후에는 **2) 워크로드 구간 전체가 `git push → ArgoCD sync` 로 대체**됩니다. → [전환 로드맵](#전환-로드맵-현재-위치)

### 검증용 명령
```bash
# Terraform 스택
terraform -chdir=<스택> fmt -check     # 포맷 검사
terraform -chdir=<스택> validate       # 문법 검증 (init 이후)
terraform -chdir=<스택> output         # 접속 주소 등 공개 값 확인

# Helm 차트 스택
helm lint <차트 디렉토리>                                    # 문법 + values.schema.json 검증
helm template <릴리스> <차트 디렉토리> | kubectl diff -f -   # 배포 전 변경 미리보기
```

---
</br>

# 🧩 배포 전 필수 준비 사항

`Terraform`/`Helm` 을 실행하기 전에 아래 작업이 **먼저 완료되어야 합니다.**
준비되지 않은 상태에서 배포하면 일부 서비스가 정상적으로 실행되지 않습니다.

| 대상 | 먼저 해야 할 작업 | 준비되지 않으면 |
|------|------------------|----------------|
| **100-base** | `longhorn_prereq` Ansible 실행 (open-iscsi, multipath, `/data/longhorn` 생성) | Longhorn 스토리지가 정상적으로 생성되지 않아 PVC 연결(Attach)에 실패합니다. |
| **102-ingress** | VIP(`192.168.56.240`)가 노드망에서 비어 있는지 확인 + VirtualBox host-only 어댑터 무차별 모드 허용 | VIP에 ARP 응답이 오지 않아 접속이 되지 않습니다(파드는 정상이라 원인 추적이 어렵습니다). |
| **인그레스 서비스 전체** | `etc_hosts` Ansible 재실행 (`--tags etc_hosts`) + 접속하는 PC의 hosts 파일 수정 | 이름이 VIP로 풀리지 않아 Grafana·Airflow·API 등이 전부 접속 불가가 됩니다. |
| **301-kafka-tools** | `kafka_ansible.yml` 실행하여 Kafka Broker 설치 | Schema Registry, Kafka UI 등이 Kafka에 연결하지 못합니다. |
| **애플리케이션 스택 전체** | MinIO, Neo4j Ansible 실행 (PostgreSQL 은 `303-postgres` 가 담당) | 데이터 저장소가 없어 애플리케이션이 계속 재시작됩니다. |
| **303-postgres** | `103-cnpg` apply + 이미지 2종(`postgres`·`cloudnative-pg`) push | CRD 가 없으면 install 이 "no matches for kind Cluster" 로 죽고, 이미지가 없으면 파드가 ImagePullBackOff 로 남습니다. |
| **304-airflow** | `303-postgres` 의 Cluster 가 healthy 상태 | init Job 이 메타 DB 에 붙지 못해 대기 루프에서 재시도만 반복합니다. |
| **306-cdc** | AP 노드의 Taint 제거 | Kafka Connect Pod 중 일부가 스케줄링되지 않고 `Pending` 상태로 남습니다. |
| **307-pipeline** | `ingest` 노드 라벨 추가 (`kubectl label node s2 ingest=true`) | `tcp-socket-collector`가 실행될 노드를 찾지 못해 `Pending` 상태가 됩니다. |
| **400-test-rdb** | 메모리 확보 (요청 합계 약 2.6Gi — 노드당 여유가 그만큼 나와야 합니다) | Oracle·SQL Server 파드가 `Pending` 으로 남습니다. 먼저 올릴 순서는 postgres → mysql → mssql → oracle 이며, 급하면 `oracle_sga_target`(기본 1536M)과 `mssql_memory_limit_mb`(기본 1024)를 낮춥니다. |
| **400-test-rdb** | 커넥터 재등록 (`data_layer_debezium/connect_json/` 4종) | 접속 주소가 s1 의 노드 IP(`192.168.56.201:1xxxx`)에서 Service DNS 로 바뀌었습니다. 옛 설정으로 등록된 커넥터는 소스에 붙지 못하고 `FAILED` 가 됩니다. |
| **모든 노드** | `etc_hosts` 설정 및 Containerd Insecure Registry 설정 | Harbor에서 이미지를 내려받지 못하거나 호스트 이름을 찾지 못합니다. |

### **요약**
>
> `Terraform`/`Helm` 은 `Kubernetes` 리소스를 배포하는 역할만 수행합니다.
> 운영체제 설정, 스토리지 준비, 데이터베이스 설치, `Kafka` 설치 등 **인프라 준비 작업은 모두 `Ansible`로 먼저 완료**해야 정상적으로 배포됩니다.

---
</br>

# 🔧 Terraform 공통 설정 (versions.tf / providers.tf)
버전과 접속 설정을 파일로 분리해 스택마다 동일한 동작을 보장합니다.
- `required_version = "1.15.8"` → CLI 버전 고정 (범위 연산자 `>=`, `~>` 금지)
- **리소스가 없는 프로바이더는 선언하지 않는다** → 스택마다 실제로 쓰는 것만 선언합니다.

| 프로바이더 | 선언한 스택 | 이유 |
|---|---|---|
| `kubernetes 2.38.0` | 102 · 301~307 · 400 | 매니페스트를 직접 만드는 스택 (`300` 은 Helm 전환 완료로 제외) |
| `helm 3.2.0` | 100 · 101 · 102 · 200 | 서드파티 차트를 쓰는 스택 |
| `harbor 3.10.21` | 200 | Harbor API로 `data-layer` 프로젝트를 만드는 스택 |

> `100-base`·`101-metallb`·`200-harbor`는 차트(+Harbor API)만 다루므로 kubernetes 프로바이더가 **없습니다.**

---
</br>

# 📑 변수(terraform.tfvars) / 시크릿(secrets.auto.tfvars)

> 일반 환경 정보와 민감한 정보를 분리하여 관리합니다.

| 파일 | 용도 | 예시 |
|------|------|------|
| `terraform.tfvars` | 환경별 설정값 (Git 관리) | Registry 주소, Image Tag, 노드 IP |
| `secrets.auto.tfvars` | 비밀번호·토큰·키 등 민감 정보 (Git 제외) | Harbor 비밀번호, API Key, CDC 소스 DB 비밀번호 |

### 📌 작성 원칙
- **환경마다 달라지는 값은 `variables.tf`에 `default`를 지정하지 않습니다.**
  - `terraform.tfvars`에 값이 없으면 `terraform plan` 단계에서 즉시 오류가 발생하여 누락을 방지합니다.
- **`secrets.auto.tfvars`는 `.gitignore`에 포함합니다.**
  - 예시는 `secrets.auto.tfvars.example`을 참고합니다.
- **호스트명(`<앱>_host`)과 남은 NodePort(`git_nodeport` 하나뿐)는 예외입니다.**
  - 모든 환경에서 동일하게 사용하므로 `variables.tf`의 `default` 값을 기준으로 관리합니다.
  - Harbor는 Ingress로 옮겨져 NodePort가 없습니다. 되살리지 마세요(접속 경로가 둘로 갈라집니다).
- **VIP(`ingress_vip`)는 `default`를 주지 않습니다.**
  - 네트워크 환경마다 달라지는 값이라 `terraform.tfvars`로 강제합니다(`102-ingress`, `305-api`).

> **Helm 전환 스택은 같은 원칙을 Helm 문법으로 구현합니다** — 환경별 값은 `values.yaml`, 필수값·형식 강제는 `values.schema.json` (누락/오타 시 `helm template` 단계에서 즉시 오류).

---
</br>

# 🗂 스택 구성

| 스택 | 도구 | 역할 | 비고 |
|------|------|------|------|
| `100-base` | Terraform | 쿠버네티스 기본 스토리지 구성 | Local Path, Longhorn 설치 (최초 1회) |
| `101-metallb` | Terraform | 온프렘 LoadBalancer 구현체 설치 | MetalLB 차트 (L2 모드, VIP 대역은 102 소유) |
| `102-ingress` | Terraform | 외부 접속 단일 진입점 구성 | VIP + ingress-nginx (Ingress 규칙은 각 앱 스택 소유) + PostgreSQL 외부 VIP 풀 |
| `103-cnpg` | Terraform | PostgreSQL 오퍼레이터 설치 | CloudNativePG (CRD+오퍼레이터만 — Cluster CR 은 `303-postgres` 소유) |
| `200-harbor` | Terraform | 컨테이너 이미지를 저장하는 사설 레지스트리 | Harbor (차트는 ClusterIP, 노출은 이 스택의 Ingress) |
| `300-data-layer-base` | **Helm ✅** | 데이터 레이어 공통 리소스 생성 | Namespace, ConfigMap, Secret, RBAC 구성 (애플리케이션 없음) |
| `301-kafka-tools` | **Helm ✅** | Kafka 운영 및 모니터링 도구 배포 | Schema Registry, Kafka UI, Exporter (브로커는 Ansible 설치) |
| `302-monitoring` | **Helm ✅** | 플랫폼 모니터링 환경 구성 | Alloy, Prometheus, Grafana |
| `303-postgres` | **Helm ✅** | 플랫폼 PostgreSQL (메타 DB 3종) | CNPG Cluster 3인스턴스 — 오퍼레이터·CRD 는 `103-cnpg`, 외부 VIP 는 `102-ingress` 소유 |
| `304-airflow` | Terraform → Helm 예정 | 데이터 파이프라인 실행 환경 구성 | DAG 는 이미지에 포함, KubernetesExecutor 사용 |
| `305-api` | Terraform → Helm 예정 | 데이터 레이어 관리 API 배포 | 매퍼 제어 및 수집기 조회 API |
| `306-cdc` | Terraform → Helm 예정 | 운영 DB 변경 데이터 수집(CDC) | Kafka Connect(Debezium) |
| `307-pipeline` | Terraform → Helm 예정 | 실제 데이터 처리 파이프라인 실행 | Mapper, Consumer, Collector 등 워크로드 배포 |
| `400-test-rdb` | Terraform → Helm 예정 | CDC 소스 RDB 4종 (테스트 픽스처) | Oracle · SQL Server · PostgreSQL · MySQL. 스키마와 CDC 활성화까지 코드가 소유 |

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

# 📜 기반 스택 (100-base)

> Kubernetes 기본 스토리지 환경을 구성하는 스택입니다.

| 구성 | 역할 |
|---|---|
| `local-path` | 기본 StorageClass. 별도 지정 없는 PVC의 기본 저장소 |
| `Longhorn` | 중요한 데이터용 고가용성 스토리지 |

## 📌 운영 기준
- `local-path` → 재생성 가능한 데이터
- `longhorn` → 장애 시 유지해야 하는 데이터
- Longhorn 복제본은 **2개** (스토리지 노드가 2개이기 때문)

## ⚠️ 주의
- 노드별 데이터 경로는 환경마다 달라 `tfvars`에서 필수 지정
  ```hcl
  longhorn_data_path = "/data/longhorn"
  ```
- 이 경로는 Ansible `longhorn_prereq`가 미리 만들어 둔 실제 마운트 경로와 같아야 합니다.

---
</br>

# 📜 LoadBalancer 스택 (101-metallb)

> 온프렘 클러스터에 `type: LoadBalancer` 기능을 제공하는 스택입니다.

## 📌 왜 필요한가
- 클라우드가 아닌 클러스터에는 `LoadBalancer` Service에 IP를 붙여 줄 주체가 없음
- 그대로 두면 Service가 영원히 `<pending>` 상태 → MetalLB가 그 자리를 채움

## 📌 구성
- MetalLB 차트 (`0.16.1`) — controller 1개 + speaker DaemonSet (전 노드)
- **차트만 설치하고 VIP 대역은 갖지 않음** → VIP는 `102-ingress`가 소유

## ⚠️ 주의사항
- `frrk8s.enabled = false` 를 반드시 지정
  - 차트 기본값이 `true`라 끄지 않으면 BGP 백엔드(frr-k8s)가 서브차트째 설치됨
  - 이 랩은 L2 모드만 사용하므로 노드마다 FRR 컨테이너가 뜨는 것은 순수 낭비
- **스택을 나눈 이유는 취향이 아니라 제약**
  - `IPAddressPool` / `L2Advertisement`는 이 차트가 만드는 **CRD**
  - 같은 스택에 두면 첫 `plan`이 타입을 찾지 못하고 실패
  - (`300` 배포(helm install) 후 `301` plan이 통과하는 것과 같은 형태)

---
</br>

# 📜 진입점 스택 (102-ingress)

> 외부 접속을 VIP 하나로 모으고 호스트명으로 갈라 보내는 스택입니다.

## 📌 구성
| 구성 | 역할 |
|---|---|
| `IPAddressPool` | VIP `192.168.56.240/32` (`autoAssign: false`) |
| `L2Advertisement` | ARP로 VIP를 광고 (BGP 아님 — 랩에 피어링할 라우터가 없음) |
| `ingress-nginx` | `replica 2`, Host 헤더로 분기 |

## 📌 운영 방식
- **Ingress 규칙은 여기서 만들지 않음** — 각 앱 스택이 자기 노출을 소유
- 앱 스택의 Ingress는 `ingressClassName: nginx`를 **반드시 명시**
  - 차트가 이 클래스를 기본값으로 만들지 않아, 빠뜨리면 조용히 404

## ⚠️ 주의사항
- `101-metallb`가 apply되어 있어야 `plan`이 통과 (CRD 제약)
- `helm_release`에 CR 2개로 `depends_on` 필수
  - helm은 EXTERNAL-IP를 기다리는데, 풀이 없으면 IP가 나오지 않아 timeout 실패
- VIP 지정은 폐기된 `spec.loadBalancerIP`가 아니라 `metallb.io/loadBalancerIPs` 어노테이션
- `externalTrafficPolicy: Local` — 이 저장소에서 유일한 예외
  - MetalLB L2는 `Local`일 때 **준비된 파드가 있는 노드에서만** VIP를 광고
- `podAntiAffinity`(required)로 replica 2를 서로 다른 노드에 배치
  - 한 노드에 뭉치면 그 노드가 죽는 순간 VIP를 광고할 노드가 사라짐
- **선행 조건**: VirtualBox host-only 어댑터의 무차별 모드 허용
  - 없으면 ARP 응답이 차단되어 VIP에 접속되지 않음 (파드는 정상이라 원인 추적이 어려움)

---
</br>

# 📜 레지스트리 스택 (200-harbor)

> 컨테이너 이미지를 저장하고 제공하는 사설 이미지 저장소(Harbor)를 구성하는 스택입니다.

## 📌 구성
- Harbor 설치 (core, portal, registry, database, redis, jobservice)
- `data-layer` 프로젝트 생성
- PVC 구성
  - Harbor 이미지 저장소 → Longhorn (30Gi)
  - Database / Redis / Jobservice → Longhorn (각 2Gi)
  - Trivy 캐시 → local-path

## ⚠️ 중요 설정
- `externalURL`은 실제 접속 주소와 반드시 동일해야 함
- HTTP 방식 사용 시 클라이언트에 insecure registry 설정 필요
  - Docker: `insecure-registries`
  - containerd: `certs.d`

## 📌 Harbor 주소는 모든 곳에서 동일해야 함

| 위치 | 값 |
|---|---|
| Harbor `externalURL` | `data-layer-harbor` |
| 각 워크로드 `harbor_registry` | `data-layer-harbor` |
| 이미지 빌드 스크립트 `REGISTRY` | `data-layer-harbor` |
| containerd `certs.d` 디렉토리명 | `data-layer-harbor` |
| Harbor Ingress 의 `host` | `data-layer-harbor` |
| Ansible `containerd_insecure_registries` | `data-layer-harbor` |

⚠️ 주소가 다르면 이미지 Push/Pull 실패

특히 containerd는 이미지 주소 문자열 기준으로 설정을 찾기 때문에, 이름과 IP를 혼용하면
HTTP Registry 설정이 적용되지 않아 Pull이 실패함.

> **인그레스 뒤에서는 IP로 우회 pull이 아예 불가능합니다.** 인그레스는 Host 헤더로 목적지를
> 고르는데 IP로 치면 헤더가 IP라서 어떤 규칙에도 걸리지 않습니다(404).

---
</br>

# 📜 공용 오브젝트 스택 (300-data-layer-base) — ✅ Helm 차트

> 데이터 레이어 전체에서 공통으로 사용하는 Kubernetes 리소스를 관리하는 스택입니다.  
> **워크로드와 이미지는 배포하지 않습니다.**  
> **Terraform 에서 Helm 차트로 전환된 첫 스택입니다** — `helm install/upgrade` 로 배포하며, 상세는 [300-data-layer-base/README.md](300-data-layer-base/README.md) 참조.

## 📌 구성
| 리소스 | 역할 |
|---|---|
| `Namespace (data-layer)` | 데이터 레이어 전용 네임스페이스 |
| `ConfigMap (data-layer-env)` | 공통 환경 설정 관리 |
| `Secret (data-layer-secrets)` | 계정, 비밀번호 등 민감 정보 관리 |
| `ClusterRoleBinding` | 파드의 Kubernetes API 접근 권한 관리 |

## 📌 외부 설치 서비스
Kafka, MinIO, Neo4j는 이 차트의 관리 대상이 아닙니다.

- Ansible로 노드에 설치
- 이 차트는 `values.yaml` 의 `global.*` 값으로 접속 정보만 조립합니다
- PostgreSQL 은 예외 — `303-postgres`(CNPG)로 K8s 에 있고, `global.postgresHost` 는
  노드 주소가 아니라 CNPG rw Service FQDN 입니다 (303 의 `clusterName` 과 같은 커밋 규칙)

## 예시
- KAFKA_BOOTSTRAP
- MINIO_S3_ENDPOINT
- COLLECTOR_DB_HOST (→ CNPG rw Service)
- PLATFORM_NEO4J_URI

## ⚠️ 운영 규칙
- `301` 이후 스택은 ConfigMap/Secret을 생성하지 않고 참조만 합니다.
  - `envFrom: configMapRef / secretRef`
- 오브젝트 이름(계약)은 Terraform 시절과 동일합니다 — 참조하는 `301~307` 은 도구 전환의 영향을 받지 않습니다.
- 값 변경은 `helm upgrade` 로만 합니다. `helm uninstall` 은 `data-layer` 네임스페이스째 삭제되므로 재설치가 아니라 **항상 upgrade** 입니다.
- 계정 및 접속 주소는 Ansible `host.yml`의 실제 설치 값과 반드시 동일해야 합니다 (PostgreSQL 만 예외 — 303-postgres 가 기준).

---
</br>

# 📜 Kafka 도구 스택 (301-kafka-tools)

> Kafka 브로커를 관리 / 모니터링하기 위한 주변 도구를 배포하는 스택입니다.  
> **Kafka 브로커 자체는 설치하지 않습니다.**

## 📌 구성
| 구성 요소 | 역할 | 포트 |
|---|---|---|
| `Schema Registry` | Kafka 스키마 관리 | `9096` |
| `Kafka UI` | Kafka 상태 확인 및 관리 | `9095` (외부는 Ingress — 포트 없음) |
| `Kafka Exporter` | Kafka 메트릭 수집 | `9097` |

## 📌 Kafka 연결 정보 관리
- 브로커 주소는 `tfvars`에 직접 입력하지 않습니다.
- `300-data-layer-base`에서 생성한 공용 ConfigMap을 참조합니다.
- 공통 설정을 사용하므로 스택 간 Kafka 주소 불일치가 발생하지 않습니다.

## ⚠️ 배포 순서
1. Kafka 브로커 설치
   - Ansible `kafka_ansible.yml`
2. 공용 리소스 생성
   - `300-data-layer-base`
3. Kafka 도구 배포
   - `301-kafka-tools`

## ⚠️ 주의사항
- `300-data-layer-base`가 먼저 적용되어 있어야 `301-kafka-tools` 실행 가능
- Kafka 브로커가 정상 실행 중이어야 Schema Registry, Kafka UI, Exporter가 연결 가능

---
</br>

# 📜 모니터링 스택 (302-monitoring)

> 서비스 상태와 성능 데이터를 수집하고 저장/조회하는 모니터링 환경입니다.

## 📌 구성
| 구성 요소 | 역할 |
|---|---|
| `Alloy` | 메트릭 수집 |
| `Prometheus` | 메트릭 저장 |
| `Grafana` | 대시보드 시각화 |

## 📌 운영 기준
- 모니터링 설정은 ConfigMap에서 관리
  - 설정 변경 시 이미지 재빌드 없이 바로 반영 가능
- Prometheus
  - 데이터 보존: `30일`
  - PVC: `20Gi` (Longhorn)
  - 보존 기간과 저장 용량은 함께 조정 필요
- Grafana
  - PVC: `5Gi` (Longhorn)
  - 대시보드 변경 정보와 DB만 저장

## ⚠️ 주의사항
- Kafka 브로커는 Kubernetes 리소스가 아니므로 자동 탐색 불가
  - JMX Exporter(`9404`)를 통해 수집
  - 대상 주소는 Ansible 설정과 동일해야 함
- Alloy는 노드 네트워크를 직접 사용
  - `alloy_port(12345)`는 노드 포트
  - 다른 서비스와 포트가 겹치면 실행 실패

---
</br>

# 📜 플랫폼 PostgreSQL 스택 (303-postgres) — Helm 차트

> 플랫폼 메타 DB 3종(`airflow` / `data_layer` / `iceberg_catalog`)을 담는
> CloudNativePG Cluster 를 구성하는 스택입니다. (구 303-git 자리 — git 스택은 퇴역)

## 📌 구성
- `Cluster` CR `data-layer-postgres` — 인스턴스 3 (primary 1 + replica 2, 노드 강제 분산)
- 이미지: `postgres`(CNPG operand 16.14 + TimescaleDB 2.29.0 — `data_pipeline/data_layer_postgres/Dockerfile`)
- 구 `initdb.d` 부트스트랩은 Cluster 스펙으로 승계:
  - `bootstrap.initdb` + `postInitApplicationSQL` → `data_layer` DB · 스키마 · 테이블 · 하이퍼테이블
  - `Database` CR 2개 → `airflow` · `iceberg_catalog`
- 앱 계정 Secret(`data-layer-postgres-app-user`, basic-auth) + 메트릭 Service + 외부 VIP Service

## 📌 운영 방식
- 클러스터 안 소비자: `data-layer-postgres-rw.data-layer.svc.cluster.local:5432` (rw = 항상 현재 primary)
- 클러스터 밖(DBeaver 등): `192.168.56.241:5432` (MetalLB 전용 VIP — 풀은 `102-ingress` 소유)
- 초기화·복제·failover 의 수행 주체는 `103-cnpg` 의 오퍼레이터 — primary 파드가 죽으면 replica 가 승격됩니다
- 스토리지는 `local-path` — 복제를 CNPG 가 하므로 longhorn 이중 복제를 피합니다

## ⚠️ 주의사항
- `103-cnpg` apply + 이미지 2종 push 가 선행돼야 합니다 (`helm template` 은 CRD 검증을 안 하므로 통과해도 안심 금물)
- **`helm uninstall` = Cluster 삭제 = PVC 까지 삭제(데이터 소실).** Database CR 삭제는 반대로 DB 를 지우지 않습니다(retain)
- 계정/DB 이름은 `300-data-layer-base` values 와, VIP 는 `102-ingress` 와 같은 커밋 규칙입니다 (차트 README 참조)
- 구 노드 로컬 PostgreSQL(Ansible, ap 의 systemd)은 퇴역 — 롤백 대비로 중지 상태로만 보존합니다

---
</br>

# 📜 Airflow 스택 (304-airflow)

> 데이터 파이프라인을 실행하는 Airflow 환경을 구성하는 스택입니다.

## 📌 구성
- Airflow API Server
- Scheduler
- DAG Processor
- Triggerer
- DB 초기화 Job

## 📌 운영 방식
- DAG·커스텀 패키지는 airflow 이미지에 포함 (`/opt/airflow/repo` — 선별 COPY, 시크릿 제외)
  - 코드 반영 = 이미지 재빌드 → `image_tag` 변경 → 롤아웃
  - 메타 DB 는 `303-postgres` 의 CNPG 클러스터 (`-rw` Service DNS)

- 실행 방식: `KubernetesExecutor`
  - 작업(Task)마다 별도 Kubernetes Pod 생성

## 📌 주요 설정
- 동시 실행 제한: `airflow_parallelism`
  - 많은 작업 실행으로 인한 리소스 과부하 방지
- Task 로그 저장:
  - MinIO S3 `airflow-logs` 버킷 사용
  - 버킷이 없으면 실행 로그가 사라질 수 있음

## ⚠️ 주의사항
- Job의 실행 템플릿(`spec.template`)은 변경 불가
  - 변경 시 `apply -replace` 필요
- `triggerer_replicas = 0`은 테스트 환경의 임시 설정
  - Deferrable Operator 사용 시 1 이상으로 변경 필요

---
</br>

# 📜 API 스택 (305-api)

> 데이터 레이어 관리 화면과 REST API를 제공하는 스택입니다.

## 📌 구성
- `data-layer-api` Deployment (replica 1 고정)
- ClusterIP Service + Ingress (`http://data-layer-api`)

## 📌 운영 방식
- 한 프로세스가 `/`(관리 화면)와 `/api`(REST)를 함께 서빙
  - 동일 출처라 CORS 설정과 화면 전용 웹서버가 필요 없음
- 상태를 파드 밖에 두어 PVC가 없음
  - DQ 규칙·도메인 설정은 MinIO, 수집 작업은 PostgreSQL

## 📌 주요 설정
- `api_proxy_body_size` (기본 `50m`)
  - Ingress 기본값 1m으로는 DQ 규칙 업로드가 413으로 실패
- `api_proxy_read_timeout` (기본 `300`초)
  - DQ '적용'은 매퍼 드레인(180) + 재기동 대기(60)를 요청 안에서 기다림
  - Ingress 기본값 60초로는 504가 발생 (NodePort 시절에는 없던 제약)
- `ingress_vip` — 파드가 Grafana를 서버사이드로 호출하기 위한 `hostAliases`
  - 대시보드 목록을 API가 대신 읽음 (브라우저가 직접 부르면 CORS)

## ⚠️ 주의사항
- `replica 1` 고정
  - `/quality/apply`가 매퍼 파드를 삭제하는 부수효과를 가져, 2개면 같은 매퍼를 두 번 죽임
- Ingress에 닿으면 인증 없는 관리 화면이 열림 (`/api/*`만 X-API-Key) — 사설망 전제

---
</br>

# 📜 CDC 스택 (306-cdc)

> 운영 DB의 변경 데이터를 Kafka로 전달하는 CDC(Change Data Capture) 환경입니다.

## 📌 구성
- Kafka Connect + Debezium
- 역할:
  - RDB 변경 로그 수집
  - `raw.*` Kafka 토픽으로 전달

## 📌 운영 방식
- 상태 정보는 Kafka 내부 토픽에 저장
  - 설정 / Offset / 상태 관리
- 따라서 StatefulSet이 아닌 `Deployment`로 운영
- 워커 장애 시 다른 워커가 마지막 Offset부터 이어서 처리
  - At-least-once 방식 (중복 데이터는 하류에서 처리)

## 📌 주요 설정
- REST 포트: `8083`
- Kafka 연결 정보는 `300-data-layer-base` 공용 ConfigMap 참조

## ⚠️ 주의사항
- `300-data-layer-base` 적용 후 배포 필요
- 커넥터 등록 시 소스 DB 비밀번호는 Terraform에서 관리하지 않고 별도 입력
- `connect_replicas = 2`는 테스트 환경 임시 설정
  - 운영 환경에서는 노드 증설 후 3개로 복구

---
</br>

# 📜 파이프라인 스택 (307-pipeline) → 데이터 처리 핵심 구성

> 실제 운영 데이터를 **수집 → 표준화 → 저장 → 관리**하는 데이터 처리 파이프라인입니다.

## CDM Mapper (8종)
- 원천 데이터(raw.*)를 분석 표준 형식(CDM)으로 변환 후 cdm-topic으로 전달
- 처리 방식이 거의 동일해 하나의 템플릿을 여러 개 재사용하는 구조

## CDM Consumer (3종)
- cdm-topic 데이터를 목적지별로 저장
- PostgreSQL / Neo4j / Iceberg 각각 독립적으로 처리하여 특정 저장소 장애가 전체 파이프라인에 영향을 주지 않음

## Lineage Consumer
- 데이터 흐름(계보) 정보를 별도로 수집해 관리
- 계보 DB 장애가 실제 데이터 처리에는 영향을 주지 않도록 분리 운영

## TCP Socket Collector
- 외부 시스템 데이터를 수집하는 전용 수집기
- 네트워크 제약 때문에 이 컴포넌트만 hostNetwork와 특정 노드 배치를 사용

## 종료 유예 시간 설정
- Mapper: 200초 → 처리 중인 데이터가 안전하게 마무리되도록 대기
- Consumer: 90초 → 배치 처리 완료 후 정상 종료 목적

## 확장 시 주의사항
- Mapper는 **모듈 8종 × replica**(기본 1) 구조입니다. 종류 수는 처리할 데이터 종류라 고정입니다.
- 늘릴 수 있는 것은 **replica이고, 상한은 소스 토픽의 파티션 수(현재 3)** 입니다.
- 3을 넘기면 남는 파드는 파티션을 배정받지 못해 아무 일도 하지 않습니다. 더 늘리려면 토픽 파티션을 먼저 늘려야 합니다.

---
</br>

# 📜 CDC 소스 RDB 스택 (400-test-rdb) → 테스트 픽스처

> Debezium이 변경을 읽어 갈 **소스 데이터베이스 4종**입니다.
> 원래 s1 서버의 docker 컨테이너였고, **그 넷 때문에 s1에만 docker를 남겨 두고 있었습니다.**
> 이 스택이 그 마지막 사유를 없애 s1의 docker를 완전히 제거할 수 있게 합니다.

## 왜 300번대가 아니라 400번대인가
- 300번대는 데이터를 **처리하는** 파이프라인이고, 이 스택은 그 **입력을 흉내 내는 테스트 픽스처**입니다.
- 실제 고객사 DB로 전환하면 이 스택은 통째로 사라집니다. 그때 300번대는 아무것도 바뀌지 않아야 합니다.
- 그래서 이 스택은 공용 ConfigMap/Secret(`data-layer-env`·`data-layer-secrets`)을 쓰지 않습니다. 자기 Secret(`test-rdb-secrets`)만 참조합니다.

## 구성

| 워크로드 | 이미지 | 내부 주소 | Debezium 캡처 방식 |
|---|---|---|---|
| `cdc-oracle` | `gvenzl/oracle-free:23.26.2-slim` | `cdc-oracle:1521` | LogMiner (redo 로그) |
| `cdc-mssql` | `mssql/server:2022-CU26` | `cdc-mssql:1433` | 네이티브 CDC (SQL Agent 잡이 적재 → 폴링) |
| `cdc-postgres` | `postgres:16.14` | `cdc-postgres:5432` | 논리복제 (pgoutput) |
| `cdc-mysql` | `mysql:8.0.46` | `cdc-mysql:3306` | binlog (복제 클라이언트) |

## 스키마와 CDC 활성화까지 코드가 소유합니다
CDC는 테이블만 있다고 동작하지 않습니다. 아래가 전부 갖춰져야 커넥터가 기동 직후 죽지 않으며, 넷 다 이 스택이 만듭니다.

| DB | 전제조건 | 만드는 주체 |
|---|---|---|
| Oracle | ARCHIVELOG · FORCE LOGGING | StatefulSet의 이미지 env |
| Oracle | `c##dbzuser` 공통유저 + 권한 · `LOGMINER_TBS` · DB/테이블 보충로깅 | 초기화 스크립트 (`/container-entrypoint-initdb.d`) |
| SQL Server | SQL Agent 기동 (`MSSQL_AGENT_ENABLED`) | StatefulSet의 이미지 env |
| SQL Server | `sp_cdc_enable_db` / `sp_cdc_enable_table` | **초기화 Job** (이미지에 훅이 없는 유일한 DB) |
| PostgreSQL | `wal_level=logical` · 복제 슬롯 수 | StatefulSet args |
| PostgreSQL | publication `cdc_test_pub` · `REPLICA IDENTITY FULL` | 초기화 스크립트 (`/docker-entrypoint-initdb.d`) |
| MySQL | `server-id` · `binlog-format=ROW` · `binlog-row-image=FULL` | StatefulSet args |
| MySQL | `REPLICATION SLAVE` / `REPLICATION CLIENT` 권한 | 초기화 스크립트 (`/docker-entrypoint-initdb.d`) |

## ⚠️ 초기화 스크립트는 빈 볼륨 첫 기동에만 실행됩니다
- 이미지 훅(Oracle·PostgreSQL·MySQL)은 데이터 디렉터리가 비어 있을 때만 돕니다. **스크립트를 고쳐도 apply만으로는 반영되지 않습니다.**
- 스키마를 바꾸려면 해당 PVC를 지우고 다시 만들어야 합니다.
  ```bash
  kubectl -n data-layer delete sts cdc-postgres
  kubectl -n data-layer delete pvc data-cdc-postgres-0     # ← 이 줄이 없으면 옛 스키마가 그대로 남습니다
  terraform -chdir=400-test-rdb apply
  ```
- SQL Server만 예외입니다. Job이 `IF NOT EXISTS`로 감싼 스크립트를 돌리므로 재실행이 안전하고, Job 이름에 스크립트 해시가 들어가 **SQL을 고치면 자동으로 한 번 더 실행됩니다.**

## 외부 접속은 port-forward로 합니다 (NodePort 없음)
소비자(Kafka Connect·Airflow)가 전부 클러스터 안이라 NodePort가 필요 없습니다. 사람이 DB 클라이언트로 붙을 때는 **docker 시절 포트를 그대로 재현**합니다.
```bash
terraform -chdir=400-test-rdb output port_forward_commands

kubectl -n data-layer port-forward svc/cdc-oracle   11521:1521
kubectl -n data-layer port-forward svc/cdc-mssql    11433:1433
kubectl -n data-layer port-forward svc/cdc-postgres 15432:5432
kubectl -n data-layer port-forward svc/cdc-mysql    13306:3306
```

## ⚠️ 커넥터 JSON의 접속 주소가 바뀌었습니다
`data_layer_debezium/connect_json/` 4종의 `database.hostname`·`database.port`가 s1 노드 IP에서 Service DNS로 바뀌었습니다. **옛 설정으로 등록해 둔 커넥터는 삭제 후 다시 등록해야 합니다.**

| 커넥터 | 이전 (docker) | 현재 (K8s) |
|---|---|---|
| `cdc-oracle-qm-control-loop` | `192.168.56.201:11521` | `cdc-oracle.data-layer.svc.cluster.local:1521` |
| `cdc-mssql-qm-qc-results` | `192.168.56.201:11433` | `cdc-mssql.data-layer.svc.cluster.local:1433` |
| `cdc-postgres-qm-event` | `192.168.56.201:15432` | `cdc-postgres.data-layer.svc.cluster.local:5432` |
| `cdc-mysql-qm-batches` | `192.168.56.201:13306` | `cdc-mysql.data-layer.svc.cluster.local:3306` |

Airflow 커넥션 4종(`cdc_oracle`·`cdc_mssql`·`cdc_postgres`·`cdc_mysql`)도 같은 주소로 다시 만들어야 `cdc_seed_loader` DAG가 동작합니다.

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