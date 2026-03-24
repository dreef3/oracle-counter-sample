-- =============================================================
-- 03_test_data.sql
-- Seed mock data so tests can verify both the "increment an
-- existing counter" and "start a brand-new counter" paths.
--
-- Rows inserted here represent counters that have already been
-- used on previous days / by other channels, giving the test
-- suite realistic starting points.
-- =============================================================

WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

-- ── Yesterday's data (closed period, should not be touched by today's tests)
INSERT INTO report_number_seq (account_number, format, output_channel, report_date, last_number)
VALUES ('ACC001', 'PDF',  'EMAIL',  TRUNC(SYSDATE) - 1, 12);

INSERT INTO report_number_seq (account_number, format, output_channel, report_date, last_number)
VALUES ('ACC001', 'PDF',  'PRINT',  TRUNC(SYSDATE) - 1,  3);

INSERT INTO report_number_seq (account_number, format, output_channel, report_date, last_number)
VALUES ('ACC002', 'XLSX', 'PORTAL', TRUNC(SYSDATE) - 1,  7);

-- ── Today's data – ACC001/PDF/EMAIL has already issued 5 reports today.
--   The next call must return '0006'.
INSERT INTO report_number_seq (account_number, format, output_channel, report_date, last_number)
VALUES ('ACC001', 'PDF',  'EMAIL',  TRUNC(SYSDATE), 5);

-- ── ACC002/XLSX/PORTAL has issued 1 report today.
--   The next call must return '0002'.
INSERT INTO report_number_seq (account_number, format, output_channel, report_date, last_number)
VALUES ('ACC002', 'XLSX', 'PORTAL', TRUNC(SYSDATE), 1);

-- ── ACC003/CSV/SFTP has no row for today → function must create it
--   and return '0001' on the first call.

COMMIT;

PROMPT Test data inserted successfully.
