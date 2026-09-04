# 302-monitoring — Helm 차트

**Terraform 스택에서 Helm 차트로 전환된 두 번째 스택**(첫 번째는 300-data-layer-base).
모니터링 3종을 만든다 — 수집(Alloy) → 저장·질의(Prometheus) → 화면(Grafana).

| 구성 | 오브젝트 | 역할 |
|---|---|---|
| Alloy | DaemonSet `alloy` | 노드마다 1개, 서버(node)·컨테이너(cadvisor) 메트릭 노출. 설정 `alloy-config` 는 이 차트 소유(`checksum/config` 자동 롤아웃) |
| Prometheus | Deployment `prometheus` + PVC `prometheus-data` + Service + Ingress | 스크랩·저장·질의. UI 는 `http://data-layer-prometheus` (무인증). 설정 `prometheus-config` 는 이 차트 소유(`checksum/config` 자동 롤아웃) |
| Grafana | Deployment `grafana` + PVC `grafana-data` + Service + Ingress | 대시보드. `http://data-layer-grafana` |

**300-data-layer-base 가 먼저 설치되어 있어야 한다** — 네임스페이스, Grafana 계정이 담긴
공용 ConfigMap/Secret, Prometheus `kubernetes_sd` 가 쓰는 API 권한(ClusterRoleBinding)이
전부 거기서 온다. 권한이 없으면 파드는 정상 기동한 채 `/targets` 만 조용히 빈다.

**수집/스크랩 설정의 소유자는 이미지가 아니라 이 차트의 ConfigMap 이다.**
alloy·prometheus 이미지는 `FROM` 한 줄(Harbor 경유 목적)이라 설정 변경에 재빌드·새 태그가 필요 없다.
설정과 파드가 **같은 릴리스**라 `checksum/config` 자동 롤아웃이 걸려 있다 — `helm upgrade` 한 번이면 끝이다:

| ConfigMap | 내용 | 소비자 | 롤아웃 트리거 |
|---|---|---|---|
| `alloy-config` | config.alloy | DaemonSet `alloy` | `checksum/config` |
| `prometheus-config` | prometheus.yml | Deployment `prometheus` | `checksum/config` |
| `grafana-datasource` | datasource.yml | Deployment `grafana` | `checksum/datasource` |

```bash
helm upgrade monitoring ./302-monitoring -f values.common.yaml -n data-layer
```

Grafana 대시보드 JSON 만은 이미지에 굽는다(`data_layer_grafana/provisioning/dashboards`) —
values 에서 파생될 값이 없는 순수 콘텐츠라서다. 고치면 재빌드 + 새 태그가 필요하다.
반대로 데이터소스는 URL 이 prometheus Service 의 네임스페이스·포트에서 파생되므로 ConfigMap 이 소유한다
(이미지에 구우면 `prometheus.port` 를 바꿔도 따라오지 않는 복사본이 된다).

수집 설정이 참조하는 값(`global.alloy.*MetricsPath`·`global.prometheus.scrapeInterval`)은
`values.common.yaml` 에 있다 — 300 이 렌더하는 파일은 없지만 값의 정의처는 그대로다.
워크로드 쪽 값은 이 차트가 소유한다
(`alloy.port`·`prometheus.retention/storageSize/storageClass/port/nodeNames`·`grafana.*`).

구 Terraform 의 `depends_on`(ConfigMap→워크로드, Service→Ingress)은 Helm 의 kind 순서 설치
(ConfigMap/PVC → 워크로드 → Ingress)가 대신한다 — 별도 장치가 없다.

## 접속 주소 (구 terraform output 승계)

내부 Service 주소(서버 간 호출)와 외부 Ingress 주소(브라우저)는 역할이 다르니 섞지 않는다:

| 용도 | 주소 | 소비자 |
|---|---|---|
| 내부 질의 | `http://prometheus.data-layer.svc.cluster.local:9090` | Grafana 데이터소스 |
| 내부 Grafana | `http://grafana.data-layer.svc.cluster.local:3000` | 305-api 서버사이드 대시보드 조회 |
| 외부 Prometheus | `http://data-layer-prometheus` | 브라우저 (디버깅 UI, 무인증) |
| 외부 Grafana | `http://data-layer-grafana` | 브라우저 / iframe |

인그레스로 열었다고 내부 호출(데이터소스 등)을 외부 이름으로 바꾸면 안 된다 —
그 이름은 파드 안에서 해석되지 않는다.

## values 계약

- `global.*` 은 **이 차트에 없다** — 저장소 루트 `values.common.yaml` 이 유일한 정의처다
  (`-f values.common.yaml`). 여기서 쓰는 것은 `namespace`(300 소유) · `harborRegistry` ·
  `imageTag`(build_and_push.sh 에 넘긴 값과 같은 불변 태그) · `ingressClassName` ·
  `hosts.grafana`/`hosts.prometheus` 다.
- `hosts.grafana` 는 300 의 `GRAFANA_URL`·`GF_SERVER_ROOT_URL` 과 같은 값에서 온다 —
  Ingress 주소와 Grafana 가 믿는 자기 주소가 어긋날 수 없다(구 grafana.host 복사본은 삭제됐다).
- `alloy.*MetricsPath` — config.alloy 컴포넌트 이름과 결합된 경로. Prometheus 스크랩 경로와
  alloy readinessProbe 가 같은 값 하나를 보므로, 컴포넌트 이름을 바꾸면 여기도 같이 바꾼다.
- kafka-jmx 잡은 파드 라벨 `app=kafka` + 포트 이름 `metrics` 로 301-kafka 브로커 파드(:9404)를 발견한다
  — static 타깃도, 복사본 값도 없다(instance = 파드 이름 kafka-N).
- `values.schema.json` 이 필수 키·형식(호스트명 밑줄 금지, host:port 형식 등)을 렌더 시점에
  강제한다 — 구 "환경 의존 변수는 default 없이 tfvars 강제" 규칙의 승계.
- 값 변경 = values 수정 → `helm upgrade`(추후에는 git push + argocd sync). kubectl 직접 수정 금지.

## 설치 (최초 1회)

전제: 300-data-layer-base 설치 완료 + Harbor 에 이미지 push 완료
(`build_and_push.sh` — alloy/prometheus/grafana 포함).

release 기록은 `data-layer` 에 둔다 — 300 과 달리 네임스페이스가 이미 있으므로
300 이 겪은 '기록 둘 곳이 아직 없는' 문제가 없다.

```bash
helm template monitoring ./302-monitoring -f values.common.yaml            # 미리보기 (클러스터 접근 없음)
helm install monitoring ./302-monitoring -f values.common.yaml -n data-layer

# 확인
helm -n data-layer ls
kubectl -n data-layer get ds/alloy deploy/prometheus deploy/grafana
# http://data-layer-prometheus/targets 에서 5개 잡이 UP 인지 확인
```

⚠ `helm uninstall monitoring -n data-layer` 는 `grafana-data`·`prometheus-data` PVC 를 모두 지운다 —
화면에서 만든 대시보드(먼저 JSON export → 이미지 provisioning 에 반영)와 보관기간치 메트릭이 사라진다.
두 PVC 는 릴리스 리소스이고 longhorn StorageClass 의 `reclaimPolicy` 가 `Delete` 라 볼륨 실체까지 삭제된다.

## 일상 운영

```bash
helm lint 302-monitoring -f values.common.yaml                                      # 문법 + 스키마 검사
helm template monitoring 302-monitoring -f values.common.yaml                       # 렌더 확인 (클러스터 접근 없음)
helm template monitoring 302-monitoring -f values.common.yaml | kubectl diff -f -   # 라이브와 대조
helm upgrade monitoring ./302-monitoring -f values.common.yaml -n data-layer        # 값/설정 변경 반영

# 재기동 없이 Prometheus 설정 리로드 (--web.enable-lifecycle)
kubectl -n data-layer exec deploy/prometheus -- wget -qO- --post-data='' http://localhost:9090/-/reload
```

## 추후 ArgoCD

이 차트는 그대로 ArgoCD Application 의 `source.path` 가 될 수 있다(300 README 와 같은 경로).
sync-wave 는 300 다음 — 공용 오브젝트가 먼저 있어야 한다는 순서 규칙을 wave 가 대신 지킨다.
