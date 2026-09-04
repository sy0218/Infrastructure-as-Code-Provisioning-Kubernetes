#!/usr/bin/env bash
# ===============================================
# [cdc-oracle 초기화 — LogMiner 전제조건 + CDC.CDC_TEST_QM_CONTROL_LOOP]
#
# 이미지의 /container-entrypoint-initdb.d 훅 → 볼륨이 빈 첫 기동에만 돈다
# ⚠ 여기서 실패하면 DB 는 이미 만들어진 뒤라 두 번째 기동엔 훅이 안 돈다 → PVC 를 지우고 다시
#
# .sh 인 이유: c##dbzuser 비밀번호를 Secret env 로 받아야 하는데 sqlplus 는 스크립트에 env 를 못 넘긴다
# ConfigMap 을 0755 로 마운트해 이미지가 source 가 아니라 실행으로 돌린다
#
# 이미지가 이미 해 주는 것: ARCHIVELOG + FRA (ENABLE_ARCHIVELOG) · FORCE LOGGING · APP_USER 스키마
#
# 커넥터 계약 — data_layer_debezium/connect_json/cdc-oracle-qm-control-loop.json
#   database.dbname  {{ .Values.oracle.cdbName }}   database.pdb.name  {{ .Values.oracle.pdbName }}
#   database.user    {{ .Values.oracle.dbzUser }}
#   table.include.list  CDC.CDC_TEST_QM_CONTROL_LOOP (Oracle 은 식별자를 대문자로 저장)
# ===============================================
set -euo pipefail

: "${DBZ_PASSWORD:?Secret test-rdb-secrets 의 DBZ_PASSWORD 가 주입되지 않았다}"

# heredoc 에 따옴표가 없다 (셸이 ${DBZ_PASSWORD} 를 끼워 넣어야 한다)
# → Oracle 식별자의 달러(CDB\$ROOT · V_\$LOG)는 백슬래시로 막는다
sqlplus -s / as sysdba <<SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO ON

-- ── 메모리 ── Free 에디션 SGA+PGA 2GB 제한. DBCA 추정값 대신 고정 (SCOPE=SPFILE → 다음 기동부터)
ALTER SYSTEM SET sga_target = {{ .Values.oracle.sgaTarget }} SCOPE = SPFILE;
ALTER SYSTEM SET pga_aggregate_target = {{ .Values.oracle.pgaAggregateTarget }} SCOPE = SPFILE;

-- ── LogMiner 테이블스페이스 ── CDB 루트와 PDB 양쪽 (공통유저가 두 곳에서 기본 TBS 를 해석한다)
CREATE TABLESPACE LOGMINER_TBS
  DATAFILE '{{ .Values.oracle.oradataPath }}/{{ .Values.oracle.cdbName }}/logminer_tbs.dbf'
  SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED;

ALTER SESSION SET CONTAINER = {{ .Values.oracle.pdbName }};
CREATE TABLESPACE LOGMINER_TBS
  DATAFILE '{{ .Values.oracle.oradataPath }}/{{ .Values.oracle.cdbName }}/{{ .Values.oracle.pdbName }}/logminer_tbs.dbf'
  SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED;
ALTER SESSION SET CONTAINER = CDB\$ROOT;

-- ── LogMiner 계정 ── c## 공통유저 (커넥터가 CDB 루트로 붙어 PDB 로 전환한다)
CREATE USER {{ .Values.oracle.dbzUser }} IDENTIFIED BY "${DBZ_PASSWORD}"
  DEFAULT TABLESPACE LOGMINER_TBS
  QUOTA UNLIMITED ON LOGMINER_TBS
  CONTAINER = ALL;

-- CONTAINER=ALL 이 빠지면 PDB 전환 직후 권한 부족으로 죽는다
GRANT CREATE SESSION            TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SET CONTAINER             TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ANY TABLE          TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ANY TRANSACTION    TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ANY DICTIONARY     TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT FLASHBACK ANY TABLE       TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT LOCK ANY TABLE            TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
-- 커넥터가 자기 플러시 테이블을 만드는 데 쓴다
GRANT CREATE TABLE              TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT CREATE SEQUENCE           TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
-- redo 마이닝 권한 → 이것만 빠져도 태스크가 기동 직후 죽는다
GRANT LOGMINING                 TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT_CATALOG_ROLE       TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT EXECUTE_CATALOG_ROLE      TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;

-- 동적 성능 뷰 — Debezium 공식 절차 목록 (버전에 따라 ANY DICTIONARY 가 V_$ 뷰를 덮지 않는다)
GRANT SELECT ON V_\$DATABASE            TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ON V_\$INSTANCE            TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ON V_\$LOG                 TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ON V_\$LOGFILE             TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ON V_\$ARCHIVED_LOG        TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ON V_\$ARCHIVE_DEST_STATUS TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ON V_\$LOGMNR_CONTENTS     TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ON V_\$LOGMNR_LOGS         TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ON V_\$TRANSACTION         TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ON V_\$SESSION             TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ON V_\$MYSTAT              TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ON V_\$STATNAME            TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;
GRANT SELECT ON V_\$PARAMETER           TO {{ .Values.oracle.dbzUser }} CONTAINER = ALL;

-- ── 보충로깅 ── DB 최소 보충로깅 (CDB 루트에서만). 없으면 LogMiner 가 변경을 재구성하지 못한다
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- ── 업무 테이블 ──
ALTER SESSION SET CONTAINER = {{ .Values.oracle.pdbName }};

-- 컬럼은 배치 경로 CSV(control_loop_defs.csv) 와 1:1. CREATED_AT/UPDATED_AT 만 DB 가 채운다 (커넥터 drop SMT 가 뺀다)
-- ⚠ 컬럼을 추가하면 커넥터 JSON 의 lower SMT(대문자→소문자) 에도 추가할 것
CREATE TABLE {{ .Values.oracle.appUser }}.cdc_test_qm_control_loop (
  control_loop_id               VARCHAR2(64)   NOT NULL,
  control_loop_name             VARCHAR2(200)  NOT NULL,
  step_code                     VARCHAR2(64)   NOT NULL,
  cv_tag                        VARCHAR2(128)  NOT NULL,
  cv_target_tag                 VARCHAR2(128),
  cv_measurement_equipment_id   VARCHAR2(64),
  cv_target_source_equipment_id VARCHAR2(64),
  mv_actuator_equipment_ids     VARCHAR2(1000),
  related_event_type_codes      VARCHAR2(1000),
  description                   VARCHAR2(4000),
  created_at                    TIMESTAMP(3)   DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                    TIMESTAMP(3)   DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_cdc_test_qm_control_loop PRIMARY KEY (control_loop_id)
);

CREATE INDEX {{ .Values.oracle.appUser }}.idx_cdc_ctrl_loop_step
  ON {{ .Values.oracle.appUser }}.cdc_test_qm_control_loop (step_code);

-- 테이블 ALL COLUMNS 보충로깅 → 없으면 UPDATE 의 before/after 에 바뀐 컬럼만 실린다
ALTER TABLE {{ .Values.oracle.appUser }}.cdc_test_qm_control_loop
  ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

EXIT
SQL

echo "CONTAINER: cdc-oracle 초기화 완료 ({{ .Values.oracle.dbzUser }} · LOGMINER_TBS · 보충로깅 · CDC.CDC_TEST_QM_CONTROL_LOOP)"
