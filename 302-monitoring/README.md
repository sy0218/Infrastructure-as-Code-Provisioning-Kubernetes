# 302-monitoring — Helm 차트

**Terraform 스택에서 Helm 차트로 전환된 두 번째 스택**(첫 번째는 300-data-layer-base).
모니터링 3종을 만든다 — 수집(Alloy) → 저장·질의(Prometheus) → 화면(Grafana).

| 구성 | 오브젝트 | 역할 |
|---|---|---|
| Alloy | DaemonSet `alloy` + ConfigMap `alloy-config` | 노드마다 1개, 서버(node)·컨테이너(cadvisor) 메트릭 노출 |
| Prometheus | StatefulSet `prometheus` + ConfigMap `prometheus-config` + Service + Ingress | 스크랩·저장·질의. UI 는 `http://data-layer-prometheus` (무인증) |
| Grafana | Deployment `grafana` + PVC `grafana-data` + Service + Ingress | 대시보드. `http://data-layer-grafana` |

**300-data-layer-base 가 먼저 설치되어 있어야 한다** — 네임스페이스, Grafana 계정이 담긴
공용 ConfigMap/Secret, Prometheus `kubernetes_sd` 가 쓰는 API 권한(ClusterRoleBinding)이
전부 거기서 온다. 권한이 없으면 파드는 정상 기동한 채 `/targets` 만 조용히 빈다.

**수집/스크랩 설정의 소유자는 이미지가 아니라 이 차트의 ConfigMap 이다.**
alloy·prometheus 이미지는 `FROM` 한 줄(Harbor 경유 목적)이라, 설정 변경에 재빌드·새 태그가
필요 없다 — 템플릿 수정 후 `helm upgrade` 하면 파드 어노테이션의 설정 해시(`checksum/config`)가
바뀌어 스스로 롤아웃된다(구 Terraform 의 `sha256(rendered)` 와 같은 원리를 Helm `sha256sum` 으로 승계).

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

- `global.*` — 네임스페이스(300 소유 — 여기서는 참조만) + Harbor 레지스트리. 추후 ArgoCD
  app-of-apps 아래에서는 루트 values 가 주입한다(단독 helm 배포 동안은 이 파일이 단일 출처).
- `imageTag` — `build_and_push.sh` 에 넘긴 값과 같은 불변 태그.
- `alloy.*MetricsPath` — config.alloy 컴포넌트 이름과 결합된 경로. Prometheus 스크랩 경로와
  alloy readinessProbe 가 같은 값 하나를 보므로, 컴포넌트 이름을 바꾸면 여기도 같이 바꾼다.
- `prometheus.kafkaJmxTargets` — 브로커는 클러스터 밖(노드 로컬 설치)이라 자동 발견이 안 되는
  유일한 static 타깃. Ansible `host.yml` kafka 그룹(노드 IP:9404)과 일치해야 한다.
- `values.schema.json` 이 필수 키·형식(호스트명 밑줄 금지, host:port 형식 등)을 렌더 시점에
  강제한다 — 구 "환경 의존 변수는 default 없이 tfvars 강제" 규칙의 승계.
- 값 변경 = values 수정 → `helm upgrade`(추후에는 git push + argocd sync). kubectl 직접 수정 금지.

## 설치 (최초 1회)

전제: 300-data-layer-base 설치 완료 + Harbor 에 이미지 push 완료
(`build_and_push.sh` — alloy/prometheus/grafana 포함).

release 기록은 `data-layer` 에 둔다 — 300 과 달리 네임스페이스가 이미 있으므로
300 이 겪은 '기록 둘 곳이 아직 없는' 문제가 없다.

```bash
helm template monitoring ./302-monitoring            # 미리보기 (클러스터 접근 없음)
helm install monitoring ./302-monitoring -n data-layer

# 확인
helm -n data-layer ls
kubectl -n data-layer get ds/alloy sts/prometheus deploy/grafana
# http://data-layer-prometheus/targets 에서 5개 잡이 UP 인지 확인
```

⚠ `helm uninstall monitoring -n data-layer` 는 `grafana-data` PVC 까지 지운다 — 화면에서 만든
대시보드가 사라진다(먼저 JSON export → 이미지 provisioning 에 반영).
Prometheus 데이터(`data-prometheus-0`)는 STS 규칙상 남아 재설치 시 다시 붙는다.

## 일상 운영

```bash
helm lint 302-monitoring                                      # 문법 + 스키마 검사
helm template monitoring 302-monitoring                       # 렌더 확인 (클러스터 접근 없음)
helm template monitoring 302-monitoring | kubectl diff -f -   # 라이브와 대조
helm upgrade monitoring ./302-monitoring -n data-layer        # 값/설정 변경 반영

# 재기동 없이 Prometheus 설정 리로드 (--web.enable-lifecycle)
kubectl -n data-layer exec prometheus-0 -- wget -qO- --post-data='' http://localhost:9090/-/reload
```

## 추후 ArgoCD

이 차트는 그대로 ArgoCD Application 의 `source.path` 가 될 수 있다(300 README 와 같은 경로).
sync-wave 는 300 다음 — 공용 오브젝트가 먼저 있어야 한다는 순서 규칙을 wave 가 대신 지킨다.
