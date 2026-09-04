# 305-api — Helm 차트

**data-layer-api.** 한 프로세스가 `/`(관리 화면)와 `/api`(REST, X-API-Key)를 서빙한다.
상태는 파드 밖(MinIO · PostgreSQL)에 있어 PVC 없는 Deployment 하나다.

| 오브젝트 | 이름 | 역할 |
|---|---|---|
| Deployment | `data-layer-api` | replicas 1 고정 — `/quality/apply` 가 매퍼 파드를 delete 하므로 둘이 동시에 처리하면 같은 매퍼를 두 번 죽인다 |
| Service | `data-layer-api` | ClusterIP `port`(8090). 이름이 외부 호스트명과 같다(파드 안은 CoreDNS, PC 는 hosts → VIP) |
| Ingress | `data-layer-api` | `http://<global.hosts.api>` — 업로드 상한·응답 대기 어노테이션은 `ingress.*` |

## values 계약

- `global.*` 은 이 차트에 없다 — 루트 `values.common.yaml` 이 정의처다(`-f values.common.yaml`).
  쓰는 것: `namespace` · `harborRegistry` · `imageTag` · `ingressClassName` · `hosts.api` · `hosts.grafana` · `ingressVip`.
- **`global.ingressVip` → 파드 `hostAliases`.** CoreDNS 는 노드 `/etc/hosts` 를 보지 않아 파드가 `GRAFANA_URL`
  의 호스트명을 못 푸는데, Grafana 대시보드 목록은 이 API 가 서버사이드로 읽는다(브라우저가 직접 부르면 CORS).
  102-ingress `ingress_vip` · Ansible `ingress_vip` 와 글자 그대로 같아야 한다.
- `port` 하나가 containerPort · Service · Ingress 백엔드 · `DATA_LAYER_API_PORT` 에 들어간다.
- `ingress.proxyReadTimeout`(300) 은 DQ '적용' 상한(드레인 180 + 재기동 대기 60 = 240초)보다 커야 한다 —
  300 의 `DATA_QUALITY_RESTART_DRAIN_TIMEOUT` · 307 의 `mapper.terminationGracePeriodSeconds` 와 한 사슬이다.
- **`resources.requests` 는 당분간 주석 처리** — 노드 여유가 없다(304-airflow 와 같은 임시 조치). 여유가 생기면 푼다.
- 권한: `serviceAccountName` 없음 → default SA. 매퍼 파드 조회/삭제 권한은 300 의 ClusterRoleBinding 하나가 준다.

## 설치

전제: 300-data-layer-base · 102-ingress 설치 완료, Harbor 에 `api:<global.imageTag>` push 완료.

```bash
helm lint 305-api -f values.common.yaml
helm template api ./305-api -f values.common.yaml
helm install api ./305-api -f values.common.yaml -n data-layer

kubectl -n data-layer get deploy,svc,ing -l app=data-layer-api
curl -s http://data-layer-api/health
```
