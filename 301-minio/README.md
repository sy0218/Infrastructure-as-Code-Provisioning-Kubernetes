# 301-minio

MinIO 단일 인스턴스 — 클러스터 내부 전용 S3 오브젝트 스토리지.

Deployment(Recreate) 1개 + RWO PVC(`longhorn`) + ClusterIP Service(9000)가 전부다.
장애는 앱 복제가 아니라 **Longhorn 스토리지 복제**로 막는다 — 301-kafka(hostNetwork + 노드
로컬 디스크 + RF 3)와 정확히 반대 전략이고, 단일 인스턴스에 longhorn 을 명시하는
100-base 규칙과 같은 계열이다(현재 longhorn PVC 사용처는 Prometheus·Grafana·MinIO 셋 —
Harbor 는 PVC 5개 모두 local-path 라 이 계열이 아니다).

이미지는 `data_pipeline/data_layer_minio/Dockerfile`(quay.io/minio/minio 재호스팅, mc 동봉) —
공용 `global.imageTag` 를 쓴다.

## 설치

```bash
helm install minio ./301-minio -f values.common.yaml -n data-layer
```

선행: 100-base(longhorn) · 300-data-layer-base(공용 Secret `data-layer-secrets` 의
`MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD`).

## 노드 장애

볼륨은 Longhorn 이 여러 노드에 복제해 두므로 데이터는 노드 장애를 넘긴다.
파드가 **자동으로** 다른 노드로 옮겨 가려면 두 가지가 맞물려야 한다:

1. 파드 퇴거 — 기본 300초 toleration 을 values `tolerationSeconds`(기본 60)로 줄였다.
2. stuck 파드 강제 삭제 — kubelet 이 죽은 노드의 파드는 Terminating 에 영원히 걸린다.
   **100-base 의 `nodeDownPodDeletionPolicy: delete-both-statefulset-and-deployment-pod`** 가
   이 파드를 지워 줘야 재스케줄 + 볼륨 reattach 가 진행된다. 이 설정이 없으면
   `kubectl delete pod --force` 를 사람이 해야 한다.

예상 RTO 는 NotReady 판정(~50초) + tolerationSeconds + reattach 로 **2~3분**. 데이터
유실은 없다(동기 복제). 대가: 쓰기가 복제 노드로 동기 전파되므로 로컬 디스크보다 느리다 —
config/스키마 버킷 용도로는 충분하다.

**검증 절차·판정 기준·복구는 [RUNBOOK.md](RUNBOOK.md) 가 소유한다.**

## 전환 (완료 — 2026-09-03)

파이프라인의 `MINIO_S3_ENDPOINT`/`CDM_OBJSTORE_ENDPOINT` 는 이 차트의 Service FQDN
(`values.common.yaml` 의 `global.minioEndpoint` = `http://minio.data-layer.svc.cluster.local:9000`)이다.
소비자가 전부 파드라 Service DNS 로 충분하고 외부 이름·노드 IP 는 쓰지 않는다. Ansible 에 MinIO
설치 롤은 없다(구 노드 로컬 설치는 퇴역 — 데이터 이관 없이 아래 '버킷' 으로 새로 시드한다).
값을 바꾼 뒤에는 `helm upgrade data-layer-base`(ConfigMap 재렌더) + 소비 워크로드 재기동이 따른다.

## 버킷 (차트가 만들지 않는다 — mc 로 한 번 부트스트랩)

파이프라인이 전제하는 버킷은 둘이다: `config`(300 의 `CDM_OBJSTORE_BUCKET` — 도메인 설정
`config/*.yaml` · DQ 규칙 `schemas/raw/*.schema.json` · Avro `schemas/*.avsc`)와 `warehouse`
(`MINIO_WAREHOUSE_BUCKET`, Iceberg). 레포의 `data_pipeline/config/`·`schemas/` 가 seed 이고
버킷 안 키는 레포 상대경로 그대로다(`objstore.py` 의 `CONFIG_PREFIX`·`RAW_SCHEMA_PREFIX`).
없으면 매퍼는 기동을 거부하고 collector DAG 은 "도메인 설정 비어있음" 으로 죽는다 — 조용한 빈 설정을 두지 않는 설계다.

```bash
POD=$(kubectl -n data-layer get pod -l app=minio -o jsonpath='{.items[0].metadata.name}')
kubectl -n data-layer exec $POD -- sh -c 'mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"'
kubectl -n data-layer exec $POD -- mc mb -p local/config local/warehouse

# seed 주입 — 레포 상대경로를 키로 그대로 쓴다. 이미지에 tar 가 없어 kubectl cp 는 안 되므로 mc pipe 로 파일마다 흘려 넣는다.
cd /project/data_pipeline
for f in config/*.yaml schemas/*.avsc schemas/raw/*.schema.json; do
  kubectl -n data-layer exec -i $POD -- mc pipe "local/config/$f" < "$f"
done
kubectl -n data-layer exec $POD -- mc ls -r local/config          # config/_common.yaml … schemas/raw/… 가 보이면 된다
```

- 재실행은 안전하다(`mb -p` 는 있으면 지나가고 `mc pipe` 는 같은 키를 레포 사본으로 덮는다).
  ⚠ UI(DQ 규칙 편집·objects 화면)로 버킷을 고친 뒤 미러하면 레포 사본이 이긴다 — 레포에 먼저 반영할 것.
- `warehouse` 는 비어 있어도 된다(cdm_consumer_warehouse 가 no-op).

## 주의

- `helm uninstall` 은 PVC 까지 지운다 — longhorn reclaimPolicy 가 Delete 라 **버킷
  데이터가 함께 삭제된다**.
- 내부 전용이라 웹 콘솔은 `MINIO_BROWSER=off` 로 꺼 뒀다(이 릴리스의 커뮤니티 콘솔은
  어차피 오브젝트 브라우저만 남았다) — 관리 작업은 mc 로 한다(이미지에 동봉).
- env 는 기본형(envFrom)이 아니라 `secretKeyRef` 로 두 키만 집는 문서화된 예외 —
  공용 env 의 `MINIO_*` 접두사 변수를 서버가 설정으로 해석할 수 있다.
