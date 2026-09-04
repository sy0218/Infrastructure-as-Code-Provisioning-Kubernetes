# CNPG 운영 매뉴얼 — data-layer-postgres

대시보드: Grafana → **CNPG 전용 모니터링** (uid `data-layer-cnpg`)
대상: `data-layer-postgres` / ns `data-layer` / 인스턴스 2 (primary+replica) / PG 16.15 + TimescaleDB 2.29.0

> `kubectl cnpg` 플러그인은 없다. 아래 명령은 전부 순수 kubectl 로 검증한 것이다.

## 1. 판정

대시보드 맨 위 「한눈에」 6개가 전부 초록이면 복제는 살아 있다. 아래 row 는 "곧 문제가 될 것"을 본다.

| 패널 | 정상 | 경고 | 위험 | 이상하면 |
|---|---|---|---|---|
| 클러스터 / Ready 인스턴스 | 초록 / `2` | — | `1` 이하 | §2.2 |
| 오퍼레이터 | 초록 | — | 빨강 | §2.1 |
| 현재 Primary | 파드명 | — | 이름 변경 | §2.4 |
| 복제 지연 | `0s` | `1s` | `5s` | §2.3 |
| 슬롯이 붙잡은 WAL | ~수 MB | 증가 추세 | `1GiB` | §2.6 |
| 접속 수 | 1~10 | `160` | `190` | §2.5 (max_connections=200) |
| 가장 긴 트랜잭션 | `0s` | `300s` | `1800s` | §2.7 |
| 트랜잭션 ID 나이 | 수백만 | `1억` | `2억` | §2.7 (한계 21억) |
| 캐시 적중률 | `0.99`↑ | `0.95` | `0.90` | shared_buffers=128MB |
| 메트릭 수집 오류 | `0` | — | `1` | 1 이면 대시보드 전체를 믿을 수 없다 |

## 2. 장애 대응

### 2.1 오퍼레이터가 죽었다
DB 는 계속 돈다. 하지만 **failover·replica 재생성·설정 반영이 멈춘다.**
```bash
kubectl -n cnpg-system logs deploy/cloudnative-pg --tail=100
kubectl -n cnpg-system rollout restart deploy/cloudnative-pg      # 대개 이걸로 끝
```

### 2.2 replica 가 죽었다
**화면:** Ready `1`, 스트리밍 replica `0`, 슬롯 활성 `0`, 「슬롯이 붙잡은 WAL」 증가 시작.
> ⚠ **복제 지연은 계속 0 으로 보인다** — 잴 대상이 없어서다. 진짜 신호는 슬롯 WAL 증가다.
```bash
kubectl -n data-layer logs data-layer-postgres-2 -c postgres --tail=100

kubectl -n data-layer delete pod data-layer-postgres-2            # 1) 대부분 여기서 끝
kubectl -n data-layer annotate pod data-layer-postgres-2 \
  alpha.cnpg.io/unrecoverable="" --overwrite                      # 2) 못 따라잡을 때만
```
> ⚠ 2번은 `pg_basebackup` 으로 **40Gi 전체를 primary 에서 다시 끌어온다.** 한가할 때 할 것.
> `nodeNames=[s1,s2]` + required anti-affinity 라 새 replica 는 **s1 에만** 갈 수 있다.

### 2.3 복제 지연이 늘어난다
「단계별 지연」에서 갈린다 — `write` 만 크면 네트워크, `replay` 만 크면 replica 디스크.
```bash
kubectl -n data-layer exec data-layer-postgres-1 -c postgres -- psql -U postgres -xc \
  "SELECT application_name, state, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"
```
「WAL 생성량」이 함께 치솟았으면 원인은 쓰기 부하다.

### 2.4 primary 가 failover 됐다
`-rw` Service 와 VIP(192.168.56.241)가 **자동으로 새 primary 를 따라간다.** 주소를 바꿀 필요 없다.
클라이언트는 한 번 끊기니 재접속만 하면 된다. 옛 primary 가 replica 로 복귀하는지 확인한다.
```bash
kubectl -n data-layer get cluster data-layer-postgres      # PRIMARY 열
```

### 2.5 접속 수가 한계에 근접
```bash
kubectl -n data-layer exec data-layer-postgres-1 -c postgres -- psql -U postgres -xc \
  "SELECT usename, state, count(*), max(now()-xact_start) AS oldest
     FROM pg_stat_activity GROUP BY 1,2 ORDER BY 3 DESC;"

# 10분 넘게 idle in transaction 인 세션 정리 — 가장 흔한 원인이자 안전한 조치
kubectl -n data-layer exec data-layer-postgres-1 -c postgres -- psql -U postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity
    WHERE state='idle in transaction' AND now()-state_change > interval '10 min';"
```

### 2.6 디스크가 찬다 ← 가장 위험
> **40Gi 는 한계가 아니다.** `local-path` 는 노드 루트 파일시스템을 그대로 쓴다(실측 160G 중 125G 여유).
> 게다가 `max_slot_wal_keep_size = -1`(무제한)이라 **replica 가 죽은 채 방치되면 WAL 을 영원히 보관한다.**
> 멈추는 지점은 노드 디스크가 꽉 찰 때뿐이고, 그러면 그 노드의 kubelet 과 다른 파드가 같이 죽는다.
```bash
# (1) 슬롯이 붙잡고 있는가 ← 제일 먼저
kubectl -n data-layer exec data-layer-postgres-1 -c postgres -- psql -U postgres -xc \
  "SELECT slot_name, active, wal_status,
          pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained
     FROM pg_replication_slots;"

# (2) 무엇이 먹는가
kubectl -n data-layer exec data-layer-postgres-1 -c postgres -- df -h /var/lib/postgresql/data
kubectl -n data-layer exec data-layer-postgres-1 -c postgres -- \
  du -sh /var/lib/postgresql/data/pgdata/pg_wal /var/lib/postgresql/data/pgdata/base
```
`active=false` 슬롯이 붙잡고 있으면 **replica 를 살리는 것이 정답**이다(§2.2). 슬롯을 지우면 재생성해야 한다.

### 2.7 긴 트랜잭션이 vacuum 을 막는다
```bash
kubectl -n data-layer exec data-layer-postgres-1 -c postgres -- psql -U postgres -xc \
  "SELECT pid, usename, state, now()-xact_start AS age, left(query,80)
     FROM pg_stat_activity WHERE xact_start IS NOT NULL ORDER BY age DESC LIMIT 5;"

# 방치된 prepared transaction — 조용히 vacuum 을 막는 대표 원인
kubectl -n data-layer exec data-layer-postgres-1 -c postgres -- psql -U postgres -c \
  "SELECT gid, prepared, owner FROM pg_prepared_xacts;"
```

## 3. 자주 쓰는 명령어

```bash
kubectl -n data-layer get cluster data-layer-postgres
kubectl -n data-layer get pod -l cnpg.io/cluster=data-layer-postgres -o wide
kubectl -n data-layer logs data-layer-postgres-1 -c postgres --tail=100

# psql — postgres 슈퍼유저는 원격 로그인이 막혀 있다(enableSuperuserAccess=false)
kubectl -n data-layer exec -it data-layer-postgres-1 -c postgres -- psql -U postgres -d data_layer

# 외부 접속은 앱 계정만 가능
psql -h 192.168.56.241 -p 5432 -U data_layer -d data_layer
kubectl -n data-layer get secret data-layer-postgres-app-user -o jsonpath='{.data.password}' | base64 -d; echo

kubectl -n data-layer delete pod <현재 primary>                    # 계획된 switchover
helm upgrade postgres ./303-postgres -f values.common.yaml -n data-layer
```

## 4. 이 대시보드가 못 보는 것

- **PVC / 파드 재시작 횟수** — kube-state-metrics 가 없다. 디스크는 §2.6 의 `df` 로 직접 본다.
- **백업** — `.spec.backup` 이 없어 아카이버 지표는 무의미하다. **지금 백업은 없다** — replica 는 이중화이지 백업이 아니다.
- **쿼리 단위 성능** — `pg_stat_statements` 미설치. 현재 실행 중인 쿼리만 §2.5 로 본다.
