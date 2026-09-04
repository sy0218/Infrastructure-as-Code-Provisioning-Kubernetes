-- ===============================================
-- [cdc-postgres 초기화 — public.cdc_test_qm_event]
--
-- 이미지의 /docker-entrypoint-initdb.d 훅 → 볼륨이 빈 첫 기동에만 돈다 (고쳐도 PVC 를 지워야 반영)
--
-- 커넥터 계약 — data_layer_debezium/connect_json/cdc-postgres-qm-event.json
--   table.include.list  public.cdc_test_qm_event
--   publication.name    {{ .Values.postgres.publication }}
--   slot.name           dbz_qm_event (슬롯은 커넥터가 만든다)
-- ===============================================

-- 컬럼은 배치 경로 CSV(event_logs.csv) 헤더와 1:1. created_at/updated_at 만 DB 가 채운다 (커넥터 drop SMT 가 뺀다)
CREATE TABLE public.cdc_test_qm_event (
    event_id     text             NOT NULL,
    batch_id     text,
    ts           timestamptz      NOT NULL,
    unit_id      text,
    equipment_id text,
    event_type   text             NOT NULL,
    severity     text,
    message      text,
    set_delta    double precision,
    created_at   timestamptz      NOT NULL DEFAULT now(),
    updated_at   timestamptz      NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id)
);

CREATE INDEX idx_cdc_event_batch_ts     ON public.cdc_test_qm_event (batch_id, ts DESC);
CREATE INDEX idx_cdc_event_equipment_ts ON public.cdc_test_qm_event (equipment_id, ts DESC);
CREATE INDEX idx_cdc_event_unit_ts      ON public.cdc_test_qm_event (unit_id, ts DESC, event_type);

-- ⚠ FULL 이 아니면 UPDATE/DELETE 의 before 이미지에 PK 만 실린다
ALTER TABLE public.cdc_test_qm_event REPLICA IDENTITY FULL;

-- publication.autocreate.mode=disabled → 없으면 커넥터가 기동 직후 죽는다
CREATE PUBLICATION {{ .Values.postgres.publication }} FOR TABLE public.cdc_test_qm_event;
