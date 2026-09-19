# 308-spark — Helm 차트

**Spark on Kubernetes 의 작업 창구.** Spark 클러스터를 상주시키지 않는다 — workbench 파드 하나가 드라이버 자리이고,
executor 는 잡이 돌 때만 파드로 떴다가 끝나면 사라진다(`spark.master k8s://`, 리소스 관리자는 쿠버네티스 자신 — YARN 없음).
Iceberg 카탈로그는 303-postgres `iceberg_catalog`(JDBC), 데이터 파일은 301-hadoop HDFS — 307 warehouse 컨슈머(pyiceberg)가 쓰는 곳과 같다.

```text
kubectl exec (spark-sql · pyspark · spark-submit /opt/spark/jobs/*.py)
   ↓
spark-workbench 파드 = 드라이버 ── K8s API ──▶ executor 파드 ×N (잡 끝나면 삭제)
   ↓                                              ↓
303-postgres iceberg_catalog (JDBC)         301-hadoop hdfs://<nameservice>/warehouse
```

| 오브젝트 | 이름 | 역할 |
|---|---|---|
| Deployment | `spark-workbench` | replicas 1 · `nodeNames` 에 nodeAffinity · `jobs.hostPath` 읽기 전용 마운트 · `sleep` 으로 대기 |
| ConfigMap | `spark-defaults` | `spark-defaults.conf` — 이미지·네임스페이스·executor 기본값·Iceberg 카탈로그(전부 global 파생). `checksum/spark-defaults` 로 롤아웃 |
| ConfigMap | `spark-hadoop-config` | `core-site.xml`/`hdfs-site.xml`(HDFS HA) — workbench 가 마운트하고, executor 는 `spark.kubernetes.hadoop.configMapName` 으로 같은 것을 받는다 |

## values 계약

- `global.*` 은 이 차트에 없다 — `-f values.common.yaml`. 쓰는 것은 `namespace` · `harborRegistry` · `imageTag` · `nodes` ·
  `hadoop`(nameservice · ports.namenodeRpc · namenode.nodeNames · warehouse) · `postgres`(clusterName · port · databases.icebergCatalog).
- **접속 주소는 파생값**: 카탈로그 URI 는 `<clusterName>-rw.<ns>.svc.cluster.local:<port>/<icebergCatalog>`, warehouse 는 `hdfs://<nameservice><warehouse.path>`,
  NameNode 주소는 `global.nodes` 표에서 IP 를 찾는다(`_helpers.tpl`). `nodeNames` 도 같은 표로 실존 검사 — 없는 이름은 렌더가 막는다(아니면 Pending 으로 조용히 멈춘다).
- `catalog`(`cdm`)는 `iceberg_tables.catalog_name` 키다 — `data_pipeline/cdm_consumer_warehouse/iceberg.py` 의 `SqlCatalog("cdm")` 과 **같은 커밋 규칙**. 다르면 서로의 테이블이 안 보인다.
- `jobs.hostPath` 는 304-airflow `repo.hostPath` 아래여야 304-airflow-rsync 가 3노드에 맞춘다(원본은 ap). hostPath `type: Directory` 라 없는 노드에서는 파드가 뜨지 않는다.
- DB 계정은 값에 없다 — 300 이 소유한 Secret `<clusterName>-app-user` 를 `secretKeyRef` 로 받아 기동 시 `spark-defaults.conf` 사본에 덧붙인다
  (파드마다 다른 `spark.driver.host`·`spark.kubernetes.driver.pod.name` 도 같은 방법). 그래서 `SPARK_CONF_DIR=/tmp/spark-conf` 다.

### 이 차트가 만들지 않는 것

- Spark 클러스터(master/worker) · Spark Operator · YARN — 없다. executor 파드는 드라이버가 K8s API 로 만든다(권한은 300 의 ClusterRoleBinding, 기본 SA).
- Service · Ingress · PVC · hook — 없다. `helm uninstall` 은 안전하다(노드의 코드는 hostPath 라 남는다).

## 설치

```bash
/project/data_pipeline/scripts/build_and_push.sh v0.1.0 spark          # 새 리포지토리라 처음 한 번은 선별 빌드해도 다른 차트의 태그를 깨지 않는다
ls /project/data_pipeline/data_layer_airflow/spark_jobs                 # ap 원본 — 304-airflow-rsync 가 s1/s2 에 맞춘다

helm lint 308-spark -f values.common.yaml
helm template spark ./308-spark -f values.common.yaml
helm install spark ./308-spark -f values.common.yaml -n data-layer
```

## 사용

```bash
kubectl -n data-layer exec -it deploy/spark-workbench -- spark-sql                          # SHOW NAMESPACES IN cdm;
kubectl -n data-layer exec -it deploy/spark-workbench -- pyspark
kubectl -n data-layer exec deploy/spark-workbench -- spark-submit /opt/spark/jobs/smoke.py  # 카탈로그·HDFS·executor 를 한 번에 검증
kubectl -n data-layer get pod -l spark-role=executor -w                                     # 잡 도는 동안만 보인다
```

- 코드는 ap 의 `jobs.hostPath` 에 저장하면 끝(rsync → 다른 노드). 재빌드도 `helm upgrade` 도 없다.
- executor 크기는 잡마다 덮어쓴다 — `spark-submit --conf spark.executor.instances=4 --conf spark.executor.memory=4g ...`.
- exec 세션이 끊기면 드라이버가 죽고 executor 도 따라 정리된다 — 긴 잡은 `nohup ... &`.

## 주의

- `spark.kubernetes.driver.pod.name` 이 workbench 파드 이름으로 박혀 있다(executor 의 ownerReference). `--deploy-mode cluster` 로 낼 일이 있으면 그 conf 를 다른 이름으로 덮어써야 한다.
- 이미지는 Spark 3.5 ↔ `iceberg-spark-runtime-3.5_2.12` 한 쌍이다(`data_pipeline/data_layer_spark/Dockerfile`). Spark 를 올리면 jar 도 같이 간다.
- Iceberg 카탈로그 테이블(`iceberg_tables` 등)은 먼저 붙는 쪽이 만든다 — pyiceberg 0.11 과 Spark JdbcCatalog 기본(V0) 스키마가 같아 어느 쪽이 먼저여도 된다.
  `jdbc.schema-version=V1` 은 켜지 말 것(pyiceberg 모델에 없는 컬럼).
- `helm upgrade` 는 checksum 으로 workbench 를 재생성한다 — 열려 있던 exec 세션과 그 안의 잡이 끊긴다.
