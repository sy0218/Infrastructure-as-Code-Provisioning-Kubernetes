# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 저장소 개요

kubeadm 3노드 랩 클러스터 위에 Terraform 스택을 레이어로 쌓는 IaC 저장소.
클러스터: ap=192.168.56.200(control-plane), s1=192.168.56.201, s2=192.168.56.202 — k8s v1.34.4, containerd.

내용물은 `/my_project/data_pipeline` 의 docker compose 스택을 쿠버네티스로 옮긴 것이다.
이름/포트/이미지/env/라벨의 단일 출처는 구현 계약서 — 스택 간 유일한 결합점이다.
**Kafka 브로커/토픽과 MinIO·PostgreSQL·Neo4j 는 K8s 에 없다** — 브로커는 ADR 0 에 따라
Ansible(`kafka_ansible.yml`)이 노드 로컬(systemd)에 설치하고, 데이터 스토어 3종도 같은 방식의
로컬 설치로 이관됐다(Ansible — 추후 작성). 파이프라인은 공용 ConfigMap 의 접속값
(`KAFKA_BOOTSTRAP`·`MINIO_S3_ENDPOINT`·`COLLECTOR_DB_HOST`·`PLATFORM_NEO4J_URI` —
전부 노드 주소 tfvars 로 조립)으로 붙는다.

## 아키텍처: 번호 디렉토리 = 독립 스택

숫자 접두사 디렉토리 하나가 독립된 Terraform 루트 모듈이며 **각자 자기 state를 가진다**.
번호 = 적용 순서, destroy 는 역순.

- `100-base` — local-path-provisioner(기본 StorageClass) + Longhorn. kubeadm 엔 기본 StorageClass 가 없어 지정 없는 PVC 는 Pending 에 걸린다. **default 는 local-path**(현재는 지정 없는 PVC 의 안전망 — 스스로 복제하던 MinIO 는 로컬 설치로 이관), 단일 인스턴스(Harbor·Prometheus·Grafana)는 `storageClassName: longhorn` 명시. **명시적 예외는 `400-test-rdb` 넷이다** — longhorn 을 쓰는 근거가 '노드가 죽어도 데이터가 살아남는 것'인데, 그 넷의 내용물은 `cdc_seed_loader` DAG 가 매일 01 시에 다시 채워 넣는 테스트 데이터라 살려 둘 이유가 없다. 반면 비용은 크다(오라클 데이터파일 6.1G × 복제 2 = 약 12G, 노드 여유 디스크가 38G 인 랩에서). 그래서 `local-path` 로 두고 `test_rdb_storage_class` 변수로만 바꿀 수 있게 했다. Longhorn 은 노드 OS 선행작업(open-iscsi/multipath/`/data/longhorn`)이 필요 — Ansible `longhorn_prereq` 롤(Terraform 밖 수동 단계).
- `101-metallb` — MetalLB(공식 차트). 온프렘이라 `type: LoadBalancer` 에 IP 를 붙여 줄 주체가 없어 Service 가 `<pending>` 에 머무는데, 그 자리를 채운다. **차트만 설치하고 VIP 대역은 갖지 않는다** — `IPAddressPool`/`L2Advertisement` 는 이 차트가 만드는 CRD 라서, 같은 스택에 두면 첫 `plan` 이 타입을 못 찾고 죽는다(`kubernetes_manifest` 는 plan 시점에 API 서버에 타입을 물어본다). ⚠ `frrk8s.enabled = false` 를 반드시 명시한다 — 차트 기본값이 `true` 라 끄지 않으면 BGP 백엔드(frr-k8s)가 서브차트째 딸려 와 노드마다 FRR 컨테이너가 뜬다(이 랩은 L2 만 쓴다).
- `102-ingress` — VIP 대역(`IPAddressPool` /32 + `L2Advertisement`) + ingress-nginx. **101 이 apply 돼 있어야 plan 이 통과한다**(위 CRD 제약 — "300 apply 후 301 plan" 과 같은 형태). `helm_release` 에 CR 두 개로 `depends_on` 을 반드시 건다: helm 은 LoadBalancer Service 가 EXTERNAL-IP 를 받을 때까지 기다리는데, 풀이 없으면 그 IP 가 영영 안 나와 timeout 으로 실패한다. VIP 요청은 폐기된 `spec.loadBalancerIP` 가 아니라 `metallb.io/loadBalancerIPs` 어노테이션으로 한다. Ingress 오브젝트는 여기서 만들지 않는다 — 각 앱 스택이 자기 노출을 소유한다.
- `200-harbor` — Harbor 레지스트리 (공식 goharbor 차트, TLS 없는 HTTP). 차트의 `expose.type` 은 **`clusterIP`** 이고 노출은 이 스택의 `manifests/harbor-ingress.yaml.tftpl` 이 소유한다(차트의 `expose.type = "ingress"` 를 쓰면 어노테이션이 values 안에 숨어 저장소 규약과 어긋난다). 그래서 이 스택만 프로바이더가 셋이다(helm·harbor·kubernetes). `externalURL` 은 실제 접속 주소와 반드시 일치해야 docker push 가 동작한다. HTTP 라서 push/pull 클라이언트에 insecure-registry 설정(docker `insecure-registries`, containerd `certs.d`)이 선행돼야 한다.
- `300-data-layer-base` — **네임스페이스 `data-layer` + 공용 ConfigMap `data-layer-env` + Secret `data-layer-secrets` + 권한 바인딩의 소유자.** 워크로드가 없고 이미지도 쓰지 않는다(`harbor_registry`/`image_tag` 변수 없음). Kafka 브로커와 MinIO·PostgreSQL·Neo4j 는 ADR 0 에 따라 노드 로컬 설치로 이관 — 이 스택은 접속값만 tfvars(`kafka_bootstrap_servers`·`minio_endpoint`·`postgres_host`·`neo4j_bolt_uri`)로 조립하며, 값은 Ansible `host.yml`·실제 설치 위치와 일치해야 한다.
- `301-kafka-tools` — schema-registry · kafka-ui · kafka-exporter. 공용 오브젝트를 만들지 않고 `envFrom` 으로 이름만 참조한다. 브로커 주소를 **tfvars 로 복사하지 않는다** — 공용 ConfigMap 을 `data "kubernetes_config_map_v1"` 로 읽어 롤아웃 해시를 뜨고(`locals.tf`), schema-registry 는 `KAFKA_BOOTSTRAP_PLAINTEXT` 키를 `configMapKeyRef` 로 받는다. 값의 정의 지점은 300 하나뿐이라 두 스택이 어긋날 수 없다. 대신 **300 이 apply 돼 있어야 301 plan 이 통과한다**(`kubernetes_manifest` 때문에 어차피 클러스터가 필요하므로 새 제약은 아니다).
- `302-monitoring` — alloy(DaemonSet, hostNetwork) + prometheus + grafana. **수집/스크랩 설정의 소유자는 이 스택의 ConfigMap 이다** — `alloy-config`(config.alloy)·`prometheus-config`(prometheus.yml) 둘 다 `manifests/*.yaml.tftpl` 에 있고, 렌더 결과의 `sha256` 을 파드 템플릿 `checksum/config` 에 심어 apply 만으로 롤아웃된다. 그래서 alloy·prometheus 이미지는 `FROM` 한 줄(Harbor 경유 목적)뿐이고 설정을 고치는 데 재빌드·새 태그가 필요 없다.
- `303-git` — **저장소 서버(`git daemon`) + Longhorn PVC.** 304 의 DAG·커스텀 패키지 원본이라 앞 번호다. 폐쇄망이라 Gitea 대신 daemon 하나(≈30Mi)만 띄우고, 인증이 없는 대신 `--enable=receive-pack` 으로 push 를 연다(Harbor 가 TLS 없는 HTTP 인 것과 같은 수준의 사설망 전제). 노드 로컬 bare 저장소가 아니라 클러스터에 둔 이유 둘: 노드가 죽어도 볼륨이 따라가고, 파드가 **Service FQDN** 으로 붙을 수 있다(노드 호스트명은 CoreDNS 가 못 푼다).
- `304-airflow` — apiserver/scheduler/dag-processor/triggerer + DB init Job. **코드는 이미지에 없다** — 파드마다 git-sync(init + 사이드카)가 303 의 저장소를 `/git/repo` 로 받아 오고, Secret 의 `AIRFLOW__CORE__DAGS_FOLDER`·`PYTHONPATH` 가 그 경로를 가리킨다. executor 는 **KubernetesExecutor** 라 태스크마다 파드가 뜬다(원형은 `executor.tf` 의 ConfigMap `airflow-pod-template`).
- `305-api` — data-layer-api. compose 의 docker socket 조작을 K8s API 어댑터로 대체했다. 권한은 이 스택이 갖지 않는다 — 아래 '권한 모델' 참조. 파드가 Grafana 를 서버사이드로 부르는 경로가 하나 있어 `ingress_vip` 로 `hostAliases` 를 채운다(아래 '외부 노출' 마지막 항목).
- `306-cdc` — kafka-connect(Debezium). 브로커 주소를 tfvars 로 복사하지 않고 301 과 같은 방식으로 공용 ConfigMap 을 `data` 로 읽는다(`locals.tf` — `KAFKA_BOOTSTRAP` 을 `configMapKeyRef` 로 받고 그 값의 해시를 파드 어노테이션에 심는다) → **300 이 apply 돼 있어야 plan 이 통과한다.**
- `307-pipeline` — cdm-mapper 8종(for_each) + 컨슈머 3종 + lineage 컨슈머 + tcp-socket-collector.
- `400-test-rdb` — **CDC 소스 RDB 4종**(cdc-oracle · cdc-mssql · cdc-postgres · cdc-mysql). 원래 s1 의 docker 컨테이너였고, 그 넷 때문에 s1 만 docker 를 살려 두고 있었다 — 이 스택이 그 마지막 사유를 없앤다. 번호가 400 인 것은 파이프라인(300번대)이 아니라 그 **입력을 흉내 내는 테스트 픽스처**라서다: 300번대는 이 스택 없이도 완결되고, 반대로 이 스택은 300번대의 어떤 오브젝트도 참조하지 않는다(공용 ConfigMap/Secret 도 쓰지 않는다 — 아래 '규칙' 참조). 스키마·계정·CDC 활성화가 곧 커넥터의 전제조건이라 **초기화 스크립트가 이 스택의 본체**다.

**스택 간 의존성은 코드에 없다.** 다른 state 의 리소스에 `depends_on` 을 걸 수 없으므로 순서는
디렉토리 번호 규칙이 담당하고, 스택 사이에 Terraform 이 모델링 못 하는 수동 단계
(이미지 빌드/push)가 존재한다. 스택 간 값 전달은 `terraform output -raw <이름>` 으로 소비한다.

## 명령어

스택마다 각자 init 부터. 루트에서 실행할 때는 `-chdir` 사용:

```bash
terraform -chdir=300-data-layer-base init && terraform -chdir=300-data-layer-base plan
terraform -chdir=300-data-layer-base fmt -check     # 포맷 검사
terraform -chdir=300-data-layer-base validate       # 문법 검증 (init 이후 가능)
```

이미지 빌드/push (앱 스택 apply 전 필수):

```bash
/my_project/data_pipeline/scripts/build_and_push.sh <TAG>
```

**`terraform apply`/`destroy` 는 사용자가 직접 실행한다.** Claude 는 파일 작성과 plan/fmt 수준
검증까지만 하고, 실행 명령어를 안내로 제공할 것.

## 규칙 (이 저장소의 비자명한 결정들)

### 공통

- **버전은 전부 정확 고정.** `>=`, `~>` 같은 범위 연산자 금지 — CLI(`required_version`), 프로바이더, Helm 차트 모두. 업그레이드는 버전 숫자를 고치는 커밋으로만 한다. 새 버전을 박기 전에 해당 레지스트리(registry.terraform.io, 차트 index.yaml)에서 실존 여부를 조회할 것.
- **리소스가 없는 프로바이더는 선언하지 않는다.** helm 프로바이더는 서드파티 차트를 쓰는 스택(100/101/102/200)에만 둔다. 102 는 차트(helm) + MetalLB CR(kubernetes)이라 둘, 200 은 차트(helm) + Harbor API(harbor) + Ingress(kubernetes)라 셋이다.
- **환경마다 달라야 하는 변수는 default 를 주지 않는다** (`harbor_registry`, `image_tag`, `longhorn_data_path` 등) — tfvars 강제로 실수를 plan 단계에서 차단.
- 파일 분리: `versions.tf` `providers.tf` `variables.tf` `terraform.tfvars` `outputs.tf` + 컴포넌트별 tf. **`main.tf` 금지** — 파일 이름이 곧 목차다.
- 주석은 한국어. "무엇"이 아니라 **"왜"** 를 적는다(무엇은 코드가 말한다).
- **섹션 배너는 아래 형식 하나로 통일한다.** 기준 구현은 `200-harbor/variables.tf` · `200-harbor/harbor.tf` — 새 파일을 쓸 때 그 톤을 따른다.

```hcl
# ===============================================
# [섹션명]
#
# 핵심 설명
# ===============================================
```

  `[섹션명]` 은 대괄호로 감싼 짧은 명사구. 설명이 필요 없으면 배너 본문 줄을 생략하고 `[섹션명]` 만 둔다.
  개별 리소스/필드에는 배너 대신 `# ...` 한두 줄을 붙인다 — 배너를 남발하면 목차 기능을 잃는다.
- **한 주제는 2~4줄로 끝낸다.** 배경이 길면 한 문장으로 요약한다. 반복 서술·compose 시절 회고·자명한 서술("이 리소스는 Deployment 를 만든다")은 적지 않는다.
- **여러 줄 `<<-EOT` description 을 쓰지 않는다.** `description` 은 한 줄 사실 서술로 두고(그대로 `terraform output`/문서에 노출된다), 배경은 위쪽 배너나 한 줄 주석으로 뺀다.
- Helm values 는 인라인 `yamlencode()` — 한 화면을 넘으면 별도 파일로 분리.
- 최소주의: remote backend, atomic, modules 등은 필요가 생기기 전까지 도입하지 않기로 결정됨.

### 시크릿

- 시크릿 변수는 `sensitive = true` + **`secrets.auto.tfvars`** 로 주입한다. `terraform.tfvars` 는 값이 눈에 띄어야 하는 환경 설정용이라 시크릿을 넣지 않는다. 스택마다 `secrets.auto.tfvars.example` 을 둔다.
- Secret/ConfigMap 은 `kubernetes_manifest` 가 아니라 **typed 리소스**(`kubernetes_secret_v1` / `kubernetes_config_map_v1`)로 만든다. `kubernetes_manifest` 는 매니페스트 전체를 state 에 평문으로 남긴다.
- ⚠ **이 저장소는 공개 전제이고, `*.tfstate` 와 `*.auto.tfvars` 를 일부러 gitignore 하지 않는다**(운영자 결정 — 랩 자격증명이라 노출돼도 실피해가 없다는 판단). **실계정을 쓰게 되는 순간 전제가 깨진다** — 그때는 `.gitignore` 에 네 줄을 되살리고 자격증명을 전량 교체해야 한다. `.terraform.lock.hcl` 은 항상 커밋.

### kubernetes_manifest + templatefile

- **템플릿 1파일 = YAML 문서 1개.** `yamldecode` 는 단일 문서만 받는다 — `---` 로 여러 문서를 넣으면 plan 이 죽는다.
- **8진수는 `0o755` 로 적는다.** `yamldecode` 는 YAML 1.2 라 `0755` 를 8진수가 아니라 **십진수 755** 로 읽는다(같은 글자를 kubectl 에 주면 YAML 1.1 이라 493 이 된다 — 그래서 인터넷의 매니페스트를 그대로 옮기면 값이 달라진다). `defaultMode`·`fsGroup` 처럼 8진수를 받는 필드가 대상이고, 허용 범위가 0~0777(십진 511)인 `defaultMode` 는 apply 가 검증에서 거부되어 그나마 눈에 띄지만 범위 제한이 없는 필드는 조용히 틀린 값이 들어간다. 현재 사례는 `400-test-rdb` 의 oracle 초기화 스크립트(실행 비트가 없으면 이미지가 source 해 버린다).
- **`--dry-run=server` 로 교차검증할 때 YAML 로 다시 덤프하지 말 것.** `plan` 의 매니페스트를 YAML 로 뽑아 kubectl 에 먹이면 `ACCEPT_EULA: Y` 같은 값이 **불리언 true** 로 재해석되어(YAML 1.1 의 y/Y/yes/on) "cannot unmarshal bool into ... type string" 이 뜬다 — 매니페스트는 멀쩡한데 검증 도구가 만들어 낸 가짜 실패다. JSON 으로 뽑으면 타입이 보존된다.
- **셸 변수는 `$${VAR}` 로 이스케이프한다.** `.yaml.tftpl` 안에서 `${...}` 는 Terraform 보간이므로, 컨테이너 command 안의 셸 변수(`$${KAFKA_BOOTSTRAP}`, `$${AIRFLOW_ADMIN_USERNAME}`, `$${tries}`)는 `$$` 로 escape 해야 리터럴로 렌더된다. 빠뜨리면 `Invalid template interpolation value` 로 plan 이 실패한다.
- `for_each` 키는 안정적인 문자열(모듈명 등). 리스트 인덱스 금지 — 순서가 바뀌면 전부 재생성된다.
- **API 서버가 기본값을 채우는 필드는 매니페스트에 명시한다.** 생략하면 apply 가 `unexpected new value ... was null, but now 1` 로 실패한다(플랜에 없던 값이 응답에 생겼다는 뜻이며, 변경 자체는 클러스터에 이미 반영된 뒤라 더 헷갈린다). 프로브의 `timeoutSeconds`·`successThreshold` 가 대표적이다 — `306-cdc` 의 `startupProbe` 가 이걸로 한 번 깨졌다.
- **컨테이너를 추가할 때는 목록 맨 뒤에 붙인다.** 이 프로바이더는 `containers` 를 이름이 아니라 **위치로** 병합한다 — 사이드카를 앞에 끼우면 기존 컨테이너와 인덱스가 어긋나 그 컨테이너의 named port 가 사라지고, `livenessProbe.httpGet.port: Invalid value: 0` 으로 apply 가 죽는다(304-airflow 에 git-sync 를 붙이며 실제로 밟았다).
- **Job 의 `spec.template` 은 불변이다.** 리소스 요청처럼 사소한 값을 바꿔도 in-place 업데이트가 거부된다 → `apply -replace=<리소스>` 로 지우고 다시 만든다. `304-airflow` 의 init Job 은 멱등이라(스키마 마이그레이션 + 계정 생성 실패 무시) 재실행이 안전하다.
- Job 은 파드 템플릿 라벨에 `controller-uid`/`job-name` 을 **생성 시점에** 붙인다. UUID 라 매니페스트에 미리 적을 수 없으므로 `computed_fields` 에 `spec.template.metadata.labels` 를 넣어 '서버가 채우는 자리'라고 알려 준다(기본값 2개를 덮어쓰므로 같이 적을 것).
- 표준형:

```hcl
resource "kubernetes_manifest" "<이름>" {
  manifest = yamldecode(templatefile("${path.module}/manifests/<파일>.yaml.tftpl", {
    namespace = var.namespace
    image     = "${var.harbor_registry}/data-layer/<img>:${var.image_tag}"
  }))
}
```

### 쿠버네티스 규약

- 모든 매니페스트에 `metadata.namespace: ${namespace}`, 공통 라벨 `app.kubernetes.io/part-of: data-layer`.
- env 주입 기본형은 `envFrom: [configMapRef: data-layer-env, secretRef: data-layer-secrets]`. 워크로드 전용 값만 `env:` 로 덧붙인다. **예외는 `400-test-rdb` 넷뿐이다** — 소스 RDB 는 파이프라인의 일부가 아니라 그 입력을 흉내 내는 픽스처라, 공용 오브젝트를 붙이면 MinIO·Neo4j 자격증명이 테스트 DB 프로세스 환경에 들어간다. 그 넷은 자기 Secret(`test-rdb-secrets`)에서 `secretKeyRef` 로 필요한 키만 집어 간다.
- **모든 파드 spec 에 `enableServiceLinks: false`.** 쿠버네티스가 네임스페이스의 Service 마다 자동 주입하는 도커 링크 시절 env 가 이름이 겹치면 컨테이너 설정을 조용히 덮어쓴다(`schema-registry` 가 `SCHEMA_REGISTRY_PORT` 로 실제로 죽었다 — 그 매니페스트에만 증상까지 남겨 뒀다). 전부 Service DNS + 공용 ConfigMap 으로 붙으므로 꺼도 잃는 것이 없다. 매니페스트에는 한 줄 주석으로 이 항목을 가리키기만 한다.
- **`data-layer` 네임스페이스와 공용 ConfigMap/Secret 을 `kubectl` 로 직접 수정하지 말 것.** `kubernetes_manifest` 는 Server-Side Apply 필드 소유권을 잡기 때문에, 수동 편집은 다음 apply 에서 field manager 충돌로 나타난다. 값 변경은 반드시 300-data-layer-base 의 tf 를 고쳐 apply 한다.
- 이미지는 예외 없이 Harbor 경유(`${harbor_registry}/data-layer/<name>:${image_tag}`), `imagePullPolicy: IfNotPresent`. 서드파티(prometheus·alloy)도 `FROM` 한 줄짜리 Dockerfile 로 `build_and_push.sh` 의 `IMAGES` 배열에서 함께 빌드해 Harbor 에 올린다 — 노드 containerd 가 Harbor 만 insecure 로 신뢰하기 때문. 태그는 불변으로 다루고 재사용하지 않는다.
- nodeSelector 는 원칙적으로 금지(기본 스케줄러에 위임). 예외는 `tcp-socket-collector` 의 `ingest: "true"` 뿐.

### 외부 노출 (Ingress 기본 · NodePort 는 예외 2개)

- **브라우저가 접속하는 HTTP 서비스는 Ingress 로 노출한다.** 진입점은 MetalLB VIP 하나(`102-ingress`)이고, 접속 주소 형식은 `http://<앱>_host` 다 — **포트가 붙지 않는다**. 갈래는 인그레스가 Host 헤더로 나누므로 서비스가 늘어도 열리는 포트는 그대로다.
- **NodePort 로 남는 예외는 하나뿐이고, 취향이 아니라 제약이다.**
  - `303-git` (30418) — `git://` 는 HTTP 가 아니라 **Host 헤더가 없다.** L7 라우팅의 전제가 성립하지 않는다(L4 로 우회해도 포트는 한 개 그대로 필요하므로 얻는 것이 없다).
  - 그 외 비-HTTP 노출은 인그레스 대상이 아니다: `tcp-socket-collector`(hostNetwork, 리슨 포트가 런타임 DB 값), `alloy`(hostNetwork DaemonSet).
- **`400-test-rdb` 의 소스 RDB 4종은 ClusterIP 뿐이다 — NodePort 를 추가하지 않는다.** 소비자(kafka-connect·airflow)가 전부 클러스터 안이라 Service DNS 로 충분하고, 사람이 DB 클라이언트로 붙는 것은 `kubectl port-forward svc/cdc-postgres 15432:5432` 처럼 **docker 시절 포트를 그대로 재현**하면 된다(명령 전체는 `terraform -chdir=400-test-rdb output port_forward_commands`). NodePort 를 열면 30000-32767 제약 때문에 어차피 옛 번호를 못 쓰므로, 접속 경로만 둘로 갈라지고 얻는 것이 없다.
- **`200-harbor` 의 host 는 접속 주소가 아니라 이미지 이름의 첫 마디다.** `data-layer-harbor/data-layer/api:v0.1.0` 에서 앞마디가 그대로 레지스트리 식별자이고, 노드 containerd 는 그 문자열과 **글자 그대로 같은** `certs.d/<이름>/hosts.toml` 디렉토리를 찾는다. 못 찾으면 기본값인 HTTPS 로 붙어 `server gave HTTP response to HTTPS client` 로 죽는다. 이름을 바꾸려면 **같은 커밋에서** 다섯 곳이 함께 가야 한다 — `harbor_host` · 전 스택 tfvars 의 `harbor_registry` · `externalURL` · harbor 프로바이더 URL · Ansible `containerd_insecure_registries`.
- **레지스트리 Ingress 에는 어노테이션 넷이 필수다.** 빠뜨리면 UI 는 멀쩡한데 `docker push` 만 죽는다 — `proxy-body-size: "0"`(레이어가 수백 MB), `proxy-request-buffering: "off"`(버퍼링하면 인그레스 임시 디스크가 먼저 참), `proxy-read-timeout`/`proxy-send-timeout` 상향(느린 랩에서 레이어 하나가 60초를 넘긴다), `ssl-redirect: "false"`(TLS 없는 HTTP 레지스트리).
- **인그레스 뒤에서는 IP 로 우회 pull 이 불가능하다.** 인그레스는 Host 헤더로 목적지를 고르는데 IP 로 치면 헤더가 IP 라서 어떤 규칙에도 걸리지 않는다(404). NodePort 시절의 "이름이 안 풀리면 IP 로" 진단 경로는 폐기됐다 — 이름 해석이 의심되면 `/etc/hosts` 와 VIP 의 ARP 응답을 먼저 본다.
- **Ingress 오브젝트는 각 앱 스택이 소유한다.** `102-ingress` 는 컨트롤러와 VIP 까지만 만든다. 매니페스트에 **`ingressClassName: nginx` 를 반드시 명시한다** — 차트가 이 클래스를 기본값으로 만들지 않아서, 빠뜨리면 어떤 컨트롤러도 집어 가지 않고 조용히 404 가 된다.
- **경로 기반이 아니라 호스트 기반으로 가른다.** 경로 기반(`/grafana`)이면 앱마다 base path 설정을 따로 넣어야 하지만(Grafana 는 `GF_SERVER_ROOT_URL` + `GF_SERVER_SERVE_FROM_SUB_PATH`), 호스트 기반은 앱이 자기가 루트에 있다고 믿어도 그대로 동작한다.
- **호스트명은 서비스마다 다르다 — `data-layer-<서비스>`.** (`data-layer-harbor`, `data-layer-kafka-ui`, `data-layer-airflow`, `data-layer-api`, `data-layer-grafana`, `data-layer-prometheus`) 주소만 보고 무엇에 접속하는지 알 수 있게 하려는 것이다. 공유 이름 `external_dns_name` 은 폐기됐다 — 되살리지 말 것.
- **호스트명은 각 스택 `variables.tf` 의 `<앱>_host` default 가 단일 출처다.** 이 이름 하나가 Ingress 의 `host`, `outputs.tf` 의 접속 URL, 300 의 `*_URL` 미러에 동시에 들어간다. 이름 전체 표의 소유자는 **README** 다 — 추가/변경하면 README 표와 variables.tf 를 같은 커밋에서 고친다. 접속 URL 은 각 스택 `outputs.tf` 에 `value = "http://${var.<앱>_host}"` 로 노출한다.
- **호스트명에 밑줄을 쓰지 않는다.** DNS 호스트명 라벨은 영문/숫자/하이픈만 허용한다(RFC 1123). 레지스트리는 특히 치명적이다 — Docker 이미지 참조 파서의 domain 규칙 때문에 `data_layer_harbor/data-layer/api:v1` 은 파싱조차 되지 않는다. `data_layer_*` 요청이 와도 구분자는 하이픈으로 간다.
- **`.local` 접미사를 쓰지 않는다.** mDNS 전용 예약 도메인(RFC 6762)이라 systemd-resolved/Avahi 가 질의를 가로챈다. hosts 파일의 단일 라벨이면 그 문제가 없다.
- **남은 NodePort 번호(git 30418)는 `variables.tf` 의 `git_nodeport` default 로 고정한다.** 환경마다 달라질 값이 아니므로 여기는 default 를 준다(다른 변수 규칙의 예외). 인그레스로 옮긴 서비스에는 이 변수를 다시 만들지 말 것 — 포트를 되살리는 순간 접속 경로가 둘로 갈라진다.
- **`externalTrafficPolicy` 는 인그레스 컨트롤러 Service 에만 `Local` 이고, 그 외에는 쓰지 않는다.** 앱 Service 는 전부 ClusterIP 라 이 필드 자체가 무의미하다(ClusterIP 에 적으면 API 서버가 거부한다). 인그레스만 `Local` 인 근거는 둘이다: ① 클라이언트 IP 가 보존된다 ② MetalLB L2 는 `Local` 일 때 '준비된 엔드포인트가 있는 노드'에서만 VIP 를 광고하므로 죽은 컨트롤러 쪽으로 트래픽이 흐르는 창이 없다. replica 1 앱에서 `Local` 이 위험했던 것과 상황이 다르다 — 여기서 엔드포인트는 노드에 흩어진 컨트롤러 자신이다.
- **인그레스 컨트롤러는 `replicaCount` 2 이상 + required podAntiAffinity(`kubernetes.io/hostname`) 로 노드에 흩는다.** 1 이면 그 파드가 전 서비스의 SPOF 이고, 2 개가 같은 노드에 뭉치면 복제본을 둔 목적이 사라진다(그 노드가 죽으면 VIP 를 광고할 노드가 없다).
- HA 는 "VIP 는 MetalLB 가 살아 있는 노드로 옮긴다" + "이름 전부가 그 VIP 하나를 가리킨다" 조합으로 성립한다. NodePort 시절의 "이름 하나에 노드 IP 3개"는 전환 주체가 **클라이언트**여서 죽은 IP 로 먼저 붙으면 TCP 타임아웃을 기다려야 했지만, VIP 는 전환 주체가 클러스터라 그 대기가 없다. 노드 `/etc/hosts` 등록은 Ansible `etc_hosts` 롤이 담당하며 **노드 IP 계열 3줄(harbor·git·minio-console·neo4j) + VIP 1줄** 구조다. 한 이름을 두 계열에 동시에 넣지 말 것 — 클라이언트가 아무 데나 붙어 증상이 매번 달라진다.
- **ClusterIP 이름/포트는 그대로 둔다.** Ingress 는 외부 접속을 추가하는 것이지 내부 계약을 바꾸지 않는다 — grafana→prometheus, airflow scheduler→apiserver 같은 클러스터 내부 호출은 계속 Service DNS + 원래 포트를 쓴다. 특히 `AIRFLOW__CORE__EXECUTION_API_SERVER_URL` 을 외부 이름으로 바꾸면 파드→VIP→인그레스→파드로 우회해 인그레스 장애가 곧 태스크 정지가 된다.
- **`data-layer-*` 호스트명은 클러스터 '밖' 이름이다 — 파드는 풀지 못한다.** 이름의 출처는 노드/PC 의 `/etc/hosts` 인데 CoreDNS 는 그 파일을 보지 않는다(`kubectl exec ... getent hosts data-layer-grafana` → NXDOMAIN). 파드가 이 이름으로 나가야 하는 예외가 생기면 그 파드에 **`hostAliases` 로 VIP 1줄**을 넣는다(NodePort 시절의 노드 IP 3줄이 아니다 — 장애 전환을 MetalLB 가 하므로 나열할 이유가 없어졌다). 현재 유일한 사례는 `305-api` → Grafana 대시보드 목록(브라우저가 직접 부르면 CORS 라 API 가 대신 읽는데, 그 주소가 브라우저용 `GRAFANA_URL` 하나뿐이다).
- **업로드 경로가 있는 Ingress 에는 `nginx.ingress.kubernetes.io/proxy-body-size` 를 붙인다.** 기본값이 1m 이라 그냥 두면 화면은 멀쩡한데 업로드만 413 으로 죽는다 — 늦게 발견되는 종류의 고장이다. 현재 대상은 `305-api`(DQ 규칙·도메인 설정 업로드).
- **응답이 오래 걸리는 동기 엔드포인트가 있는 Ingress 에는 `nginx.ingress.kubernetes.io/proxy-read-timeout` 을 함께 붙인다.** 기본값이 60초라, NodePort(L4)에는 없던 504 가 인그레스를 끼우는 순간 생긴다. 현재 대상은 `305-api` — DQ '적용'이 매퍼 드레인(`DATA_QUALITY_RESTART_DRAIN_TIMEOUT`=180) + 재기동 대기(60) = 최대 240초를 **HTTP 요청 안에서** 기다린다. 드레인 값을 올리면 이 타임아웃도 같이 올려야 한다(`307-pipeline` 의 `cdm_mapper_termination_grace_seconds` 까지 한 사슬이다).

### 권한 모델 — 워크로드별 RBAC 을 두지 않는다

1인 운영 환경이라 권한 분리를 하지 않기로 했다. 권한 오브젝트는 **`300-data-layer-base/permissions.tf` 의 ClusterRoleBinding 하나뿐**이며, `data-layer` 네임스페이스의 `default` ServiceAccount 에 `cluster-admin` 을 준다.

- 워크로드 매니페스트에 **`serviceAccountName` 을 쓰지 않는다**(default SA 가 자동 적용). ServiceAccount / Role / RoleBinding / ClusterRole 을 새로 만들지 말 것.
- **"RBAC 을 껐다"가 아니다.** kube-apiserver 가 `--authorization-mode=Node,RBAC` 으로 뜨므로 바인딩이 하나도 없으면 파드의 API 호출은 전부 403 이 된다. 그러면 data-layer-api 의 DQ '적용'(매퍼 재기동)·수집기 상태 조회가 실패하고, prometheus 는 `kubernetes_sd` 가 아무것도 못 찾아 `/targets` 가 **조용히** 빈다(파드는 정상 기동한다 — 증상이 안 보여서 더 위험하다). 관리 부담을 없애는 방법은 객체를 지우는 게 아니라 '한 번 주고 다시 안 건드리는' 이 형태다.
- 대가: 이 네임스페이스의 모든 파드가 클러스터 관리자 권한을 갖는다. 사용자가 늘거나 신뢰 경계가 생기면 이 파일을 지우고 워크로드별 Role 로 되돌리는 것이 정공법이다.
