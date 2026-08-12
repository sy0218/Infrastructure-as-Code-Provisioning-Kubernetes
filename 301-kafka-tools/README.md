# 301-kafka-tools — Helm 차트

**Kafka 운영 도구 3종.** 300-data-layer-base 가 만든 공용 오브젝트(Namespace·ConfigMap·Secret)를
이름으로만 참조하고, 자기 공용 오브젝트는 만들지 않는다. 추후 ArgoCD app-of-apps 에서는
sync-wave 1 (300 다음)이다.

| 오브젝트 | 이름 | 역할 |
|---|---|---|
| Deployment + Service | `schema-registry` | Avro 스키마 저장·검증 — 매퍼·컨슈머·kafka-ui 가 전부 여기를 본다 (포트 9096) |
| Deployment + Service | `kafka-ui` | 토픽·컨슈머 그룹 웹 콘솔 (포트 9095) |
| Deployment + Service | `kafka-exporter` | 토픽·오프셋·Lag 을 Prometheus 메트릭으로 노출 — 302-monitoring 이 긁어간다 (포트 9097) |
| Ingress | `kafka-ui` | 브라우저 진입점 — `http://data-layer-kafka-ui` (Host 기반, 포트 없음) |

## values 계약

- `global.*` — 네임스페이스 + 배포 공통값(harborRegistry·imageTag·ingressClassName)과
  `kafkaBootstrap` **복사본**. 추후 ArgoCD app-of-apps 아래에서는 루트 values 가 한 번에 주입한다.
- 나머지 최상위 키 — 이 차트가 소유한 값(포트 3종·복제 수·`kafkaUiHost`).
- `values.schema.json` 이 필수 키·형식(호스트명 밑줄 금지, host:port 형식 등)을 렌더 시점에
  강제한다 — 구 "환경 의존 변수는 default 없이 tfvars 강제" 규칙의 승계.

### 복사본 값 두 방향 (바꿀 때 같은 커밋에서 함께)

- `global.kafkaBootstrap` ← 300 이 원본. 워크로드는 실제 값을 클러스터의 공용 ConfigMap 에서
  받으므로 복사본이 어긋나도 접속은 깨지지 않지만, 값 변경 시 파드를 재기동시키는
  checksum 이 어긋난다. (구 Terraform 은 클러스터의 ConfigMap 을 data 로 읽어 해시했는데,
  helm template 은 클러스터를 못 읽어 복사본 방식으로 바꿨다 — 대신 "300 apply 후에만
  301 plan 가능" 제약이 사라졌다.)
- `schemaRegistryPort` · `kafkaUiHost` → 300 이 URL 문자열(`SCHEMA_REGISTRY_URL`·`KAFKA_UI_URL`)
  조립용 복사본을 갖는다. 이 차트가 원본.

## 설치

전제: 300-data-layer-base 설치 완료 + 이미지 3종이 Harbor 에 push 되어 있을 것
(`/my_project/data_pipeline/scripts/build_and_push.sh <TAG>`), kafka-ui 접속은 102-ingress 필요.

release 를 `data-layer` 에 두는 이유: 300 과 달리 네임스페이스가 이미 있고,
이 차트의 오브젝트 전부가 그 안에 있다 — 기록과 실체를 한곳에 둔다.

```bash
helm lint 301-kafka-tools                                  # 문법 + 스키마 검사
helm template kafka-tools ./301-kafka-tools                # 미리보기 (클러스터 접근 없음)
helm install kafka-tools ./301-kafka-tools -n data-layer

# 확인
helm -n data-layer ls
kubectl -n data-layer rollout status deploy/schema-registry deploy/kafka-ui deploy/kafka-exporter
kubectl -n data-layer get ingress kafka-ui                 # HOSTS: data-layer-kafka-ui
curl -s http://data-layer-kafka-ui | head -1               # VIP 를 푸는 PC 에서
```

## 일상 운영

```bash
helm lint 301-kafka-tools                                       # 문법 + 스키마 검사
helm template kafka-tools 301-kafka-tools                       # 렌더 확인 (클러스터 접근 없음)
helm template kafka-tools 301-kafka-tools | kubectl diff -f -   # 라이브와 대조
helm upgrade kafka-tools ./301-kafka-tools -n data-layer        # 값 변경 반영
helm uninstall kafka-tools -n data-layer                        # 이 스택만 제거(공용 오브젝트는 무관)
```

## 추후 ArgoCD

이 차트는 그대로 ArgoCD Application 의 `source.path` 가 될 수 있다. `global.*` 는 app-of-apps
루트 values 가 주입하므로 `kafkaBootstrap` 복사본 수동 동기화도 그때 없어진다.
