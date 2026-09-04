-- ===============================================
-- [cdc-mysql 초기화 — {{ .Values.mysql.database }}.cdc_test_qm_batches]
--
-- 이미지의 /docker-entrypoint-initdb.d 훅 → 볼륨이 빈 첫 기동에만 돈다 (고쳐도 PVC 를 지워야 반영)
-- 접속은 root, 기본 DB 는 MYSQL_DATABASE (entrypoint 가 --database 를 붙인다)
--
-- 커넥터 계약 — data_layer_debezium/connect_json/cdc-mysql-qm-batches.json
--   database.include.list  {{ .Values.mysql.database }}
--   table.include.list     {{ .Values.mysql.database }}.cdc_test_qm_batches
--   database.user          {{ .Values.mysql.user }}
-- ===============================================

-- 컬럼은 배치 경로 CSV(batches.csv) 헤더와 1:1. created_at/updated_at 만 DB 가 채운다 (커넥터 drop SMT 가 뺀다)
-- ⚠ updated_at 의 ON UPDATE 가 핵심 → 값이 안 바뀐 UPDATE 는 binlog 레코드가 없다. 이 절이 재적재를 CDC 이벤트로 만든다
CREATE TABLE cdc_test_qm_batches (
    batch_id    varchar(64)  NOT NULL,
    unit_id     varchar(64)  NOT NULL,
    batch_start datetime(3)  NOT NULL,
    batch_end   datetime(3)  DEFAULT NULL,
    `shift`     varchar(16)  NOT NULL,
    created_at  timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at  timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (batch_id),
    KEY idx_batches_time (batch_start, batch_end),
    KEY idx_batches_shift (`shift`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 이미지가 주는 것은 GRANT ALL ON {{ .Values.mysql.database }}.* 뿐 → Debezium 은 전역 권한이 더 필요하다
--   REPLICATION SLAVE(binlog 스트림) · REPLICATION CLIENT(시작 위치) · RELOAD/LOCK TABLES(스냅샷 락) · SELECT/SHOW DATABASES(메타데이터)
GRANT SELECT, RELOAD, SHOW DATABASES, LOCK TABLES, REPLICATION SLAVE, REPLICATION CLIENT
    ON *.* TO '{{ .Values.mysql.user }}'@'%';
FLUSH PRIVILEGES;
