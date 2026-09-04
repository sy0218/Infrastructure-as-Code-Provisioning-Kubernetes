-- ===============================================
-- [cdc-mssql 초기화 — {{ .Values.mssql.database }}.dbo.cdc_test_qm_qc_result + 네이티브 CDC]
--
-- 이미지에 초기화 훅이 없어 Job(helm hook, post-install/upgrade) 이 돌린다
-- → 여러 번 돌아도 되게 전부 IF NOT EXISTS
--
-- 커넥터 계약 — data_layer_debezium/connect_json/cdc-mssql-qm-qc-results.json
--   database.names      {{ .Values.mssql.database }}
--   table.include.list  dbo.cdc_test_qm_qc_result
--   database.user       sa
-- ===============================================

IF DB_ID(N'{{ .Values.mssql.database }}') IS NULL
BEGIN
    -- 복구 모델은 model 을 따라 FULL. SIMPLE 로 바꾸지 말 것 (로그 조기 재사용으로 캡처 누락)
    EXEC (N'CREATE DATABASE [{{ .Values.mssql.database }}]');
END
GO

USE [{{ .Values.mssql.database }}];
GO

-- 컬럼은 배치 경로 CSV(qc_results.csv) 헤더와 1:1. created_at/updated_at 만 DB 가 채운다 (커넥터 drop SMT 가 뺀다)
-- ⚠ qc_ts 는 DATETIME2 → Debezium 이 epoch 정수로 내보내고 커넥터 ts1 SMT 가 문자열로 되돌린다
IF OBJECT_ID(N'dbo.cdc_test_qm_qc_result', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.cdc_test_qm_qc_result (
        batch_id     NVARCHAR(64)   NOT NULL,
        qc_ts        DATETIME2(3)   NOT NULL,
        unit_id      NVARCHAR(64)   NULL,
        qc_target    FLOAT          NULL,
        qc_score     FLOAT          NULL,
        qc_deviation FLOAT          NULL,
        qc_pass      BIT            NULL,
        defect_list  NVARCHAR(1000) NULL,
        created_at   DATETIME2(3)   NOT NULL CONSTRAINT df_cdc_qc_created DEFAULT SYSUTCDATETIME(),
        updated_at   DATETIME2(3)   NOT NULL CONSTRAINT df_cdc_qc_updated DEFAULT SYSUTCDATETIME(),
        CONSTRAINT pk_cdc_test_qm_qc_result PRIMARY KEY CLUSTERED (batch_id)
    );

    CREATE NONCLUSTERED INDEX idx_cdc_qc_ts   ON dbo.cdc_test_qm_qc_result (qc_ts);
    CREATE NONCLUSTERED INDEX idx_cdc_qc_pass ON dbo.cdc_test_qm_qc_result (qc_pass);
END
GO

-- DB 단위 CDC → cdc 스키마 + cdc_capture/cdc_cleanup SQL Agent 잡
-- ⚠ MSSQL_AGENT_ENABLED 가 꺼져 있으면 잡이 돌지 않아 커넥터는 RUNNING 인데 토픽만 빈다
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'{{ .Values.mssql.database }}' AND is_cdc_enabled = 1)
BEGIN
    EXEC sys.sp_cdc_enable_db;
END
GO

-- 테이블 단위 CDC. @role_name NULL = 게이팅 롤 없음 (sa 로 붙는다). @supports_net_changes 는 PK 전제
IF NOT EXISTS (SELECT 1 FROM cdc.change_tables WHERE capture_instance = N'dbo_cdc_test_qm_qc_result')
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema        = N'dbo',
        @source_name          = N'cdc_test_qm_qc_result',
        @role_name            = NULL,
        @supports_net_changes = 1;
END
GO
